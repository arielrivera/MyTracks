#!/usr/bin/env python3
"""
Ariel's Splitter - Demucs-based music source separation script.
Called by the Swift app via Process/Foundation.
"""

import sys
import json
import os
import hashlib
import warnings
import time
import threading
warnings.filterwarnings('ignore')

def monitor_resources(stop_event):
    """Monitor CPU and memory usage of this process and emit RESOURCE lines."""
    try:
        import psutil
        process = psutil.Process(os.getpid())
        while not stop_event.is_set():
            cpu = process.cpu_percent(interval=1.0)
            mem = process.memory_info().rss / (1024 * 1024 * 1024)  # GB
            print(f"RESOURCE:CPU:{cpu:.1f}:MEM:{mem:.2f}", flush=True)
    except Exception as e:
        print(f"WARNING:Resource monitor error: {e}", flush=True)

def start_resource_monitor(stop_event):
    try:
        import psutil
        t = threading.Thread(target=monitor_resources, args=(stop_event,), daemon=True)
        t.start()
    except Exception as e:
        print(f"WARNING:Could not start resource monitor: {e}", flush=True)

def sha256_file(path):
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()

def separate(input_file, output_dir, stems_to_extract, model_name="htdemucs"):
    """
    Separate audio using Demucs.
    """
    if not os.path.exists(input_file):
        print(f"ERROR:Input file not found: {input_file}", flush=True)
        sys.exit(1)
    
    if not os.path.isdir(output_dir):
        try:
            os.makedirs(output_dir, exist_ok=True)
        except Exception as e:
            print(f"ERROR:Could not create output directory {output_dir}: {e}", flush=True)
            sys.exit(1)
    
    resource_stop_event = threading.Event()
    start_resource_monitor(resource_stop_event)
    
    import numpy as np
    import torch
    import soundfile as sf
    from demucs import pretrained
    from demucs.apply import apply_model
    from demucs.audio import convert_audio
    import librosa
    
    device = "cpu"
    if torch.cuda.is_available():
        device = "cuda"
    elif torch.backends.mps.is_available():
        device = "mps"
    
    print(f"DEVICE:{device}", flush=True)
    
    # Load model
    print(f"STATUS:Loading model {model_name}...", flush=True)
    print(f"PROGRESS:0.00", flush=True)
    model = pretrained.get_model(model_name)
    model.to(device)
    model.eval()
    
    print(f"MODEL_SOURCES:{json.dumps(model.sources)}", flush=True)
    
    # Load audio
    print(f"STATUS:Loading audio file...", flush=True)
    print(f"PROGRESS:0.05", flush=True)
    wav, sr = librosa.load(input_file, sr=None, mono=False)
    
    # librosa with mono=False returns shape (channels, samples) for stereo
    # or (samples,) for mono
    if wav.ndim == 1:
        # Mono - convert to (1, samples)
        wav = wav[np.newaxis, :]
    
    # Ensure we have exactly 2 channels for Demucs
    if wav.shape[0] > 2:
        wav = wav[:2, :]  # Take first 2 channels
    elif wav.shape[0] == 1:
        # Duplicate mono to stereo
        wav = np.repeat(wav, 2, axis=0)
    
    # Convert to torch tensor
    wav_tensor = torch.from_numpy(wav).float()
    
    # Convert to model's sample rate if needed
    model_sr = getattr(model, 'samplerate', 44100)
    if sr != model_sr:
        wav_tensor = convert_audio(wav_tensor, sr, model_sr, model.audio_channels)
    
    # Add batch dimension: (1, channels, samples)
    wav_tensor = wav_tensor.unsqueeze(0).to(device)
    
    # Apply model
    print(f"STATUS:Separating tracks...", flush=True)
    print(f"PROGRESS:0.10", flush=True)
    
    # Suppress tqdm output by patching the tqdm module
    import tqdm as tqdm_module
    from tqdm import tqdm
    
    original_tqdm_class = tqdm_module.tqdm
    
    class SilentTqdm(original_tqdm_class):
        def __init__(self, *args, **kwargs):
            kwargs['disable'] = True
            super().__init__(*args, **kwargs)
        def update(self, n=1):
            super().update(n)
        def close(self):
            super().close()
        def set_postfix(self, *args, **kwargs):
            pass
    
    tqdm_module.tqdm = SilentTqdm
    
    class ProgressReporter:
        def __init__(self, total):
            self.total = total
            self.n = 0
            self.last_reported = 0.10
        def update(self, n=1):
            self.n += n
            progress = 0.10 + 0.80 * (self.n / self.total)
            if progress - self.last_reported >= 0.02:
                print(f"PROGRESS:{progress:.2f}", flush=True)
                self.last_reported = progress
        def close(self):
            pass
        def set_postfix(self, *args, **kwargs):
            pass
    
    # Estimate number of chunks for progress reporting
    sample_length = wav_tensor.shape[-1]
    chunk_size = int(model.samplerate * 7.8)
    num_chunks = max(1, (sample_length + chunk_size - 1) // chunk_size)
    
    pbar = ProgressReporter(num_chunks)
    
    with torch.no_grad():
        sources = apply_model(model, wav_tensor, device=device, shifts=1, split=True, overlap=0.25, progress=pbar)
    
    # Restore tqdm
    tqdm_module.tqdm = original_tqdm_class
    
    pbar.update(pbar.total - pbar.n)  # ensure 90%
    resource_stop_event.set()
    
    # sources shape: (1, num_sources, channels, samples)
    sources = sources[0]  # Remove batch dimension -> (num_sources, channels, samples)
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    print(f"PROGRESS:0.90", flush=True)
    
    total_sources = len(stems_to_extract)
    for idx, stem_name in enumerate(stems_to_extract):
        stem_lower = stem_name.lower()
        
        # Find matching source in model
        matched_source = None
        for demucs_source in model.sources:
            if stem_lower == demucs_source.lower():
                matched_source = demucs_source
                break
        
        if matched_source is None:
            for demucs_source in model.sources:
                if stem_lower in demucs_source.lower() or demucs_source.lower() in stem_lower:
                    matched_source = demucs_source
                    break
        
        if matched_source is None:
            print(f"WARNING:Could not find source for '{stem_name}', skipping", flush=True)
            continue
        
        source_idx = model.sources.index(matched_source)
        source_audio = sources[source_idx].cpu().numpy()  # (channels, samples)
        
        # Convert back to original sample rate if needed
        if sr != model_sr:
            source_audio = librosa.resample(source_audio, orig_sr=model_sr, target_sr=sr, axis=-1)
        
        # Transpose from (channels, samples) to (samples, channels) for soundfile
        source_audio = source_audio.T
        
        output_path = os.path.join(output_dir, f"{stem_name}.wav")
        try:
            sf.write(output_path, source_audio, sr)
        except Exception as e:
            print(f"WARNING:Could not write {stem_name} to {output_path}: {e}", flush=True)
            continue
        
        # Compute hash
        try:
            file_hash = sha256_file(output_path)
            print(f"FILE:{stem_name}:{output_path}:{file_hash}", flush=True)
        except Exception as e:
            print(f"WARNING:Could not hash {stem_name}: {e}", flush=True)
        
        progress = 0.90 + 0.10 * ((idx + 1) / total_sources)
        print(f"PROGRESS:{progress:.3f}", flush=True)
    
    print("DONE", flush=True)

if __name__ == "__main__":
    import numpy as np
    
    if len(sys.argv) < 2:
        print("Usage: separate.py <command> [args...]")
        print("Commands: separate, model_info")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "separate":
        if len(sys.argv) < 5:
            print("Usage: separate.py separate <input_file> <output_dir> <stems_json> [model_name]")
            sys.exit(1)
        
        input_file = sys.argv[2]
        output_dir = sys.argv[3]
        stems_to_extract = json.loads(sys.argv[4])
        model_name = sys.argv[5] if len(sys.argv) > 5 else "htdemucs"
        
        separate(input_file, output_dir, stems_to_extract, model_name)
    
    elif command == "model_info":
        from demucs import pretrained
        models_to_check = ['htdemucs', 'htdemucs_ft', 'htdemucs_6s']
        available = {}
        for name in models_to_check:
            try:
                model = pretrained.get_model(name)
                available[name] = list(model.sources)
            except Exception as e:
                available[name] = str(e)
        print(json.dumps(available, indent=2))
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)