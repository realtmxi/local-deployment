import os
import re
import argparse
import matplotlib.pyplot as plt

def parse_log_file(filepath):
    """
    Reads a log file and extracts the Mean TTFT (ms) and Mean ITL (ms).
    Returns a dictionary of metrics or None if parsing fails.
    """
    metrics = {}
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        ttft_match = re.search(r"Mean TTFT \(ms\):[ ]*(\d+\.?\d+)", content)
        if ttft_match:
            metrics['ttft'] = float(ttft_match.group(1))

        itl_match = re.search(r"Mean ITL \(ms\):[ ]*(\d+\.?\d+)", content)
        if itl_match:
            metrics['itl'] = float(itl_match.group(1))

        req_throughput_match = re.search(r"Request throughput \(req/s\):[ ]*(\d+\.?\d+)", content)
        if req_throughput_match:
            metrics['req_throughput'] = float(req_throughput_match.group(1))

        token_throughput_match = re.search(r"Output token throughput \(tok/s\):[ ]*(\d+\.?\d+)", content)
        if token_throughput_match:
            metrics['token_throughput'] = float(token_throughput_match.group(1))

        # A file is only valid if it has at least one latency and one throughput metric
        has_latency = 'ttft' in metrics or 'itl' in metrics
        has_throughput = 'req_throughput' in metrics or 'token_throughput' in metrics
        if not (has_latency and has_throughput):
            print(f"Warning: Skipping file due to missing metrics: {filepath}")
            return None

        return metrics

    except Exception as e:
        print(f"Error processing file {filepath}: {e}")
        return None

def extract_parameters_from_filename(filename):
    """
    Extracts prompt length and concurrency from the filename.
    e.g., 'a100-2gpu-llama-70b-prompt-128-concurrency-1.log' -> (128, 1)
    """
    pattern = r"prompt-(\d+)-concurrency-(\d+)\.log"
    match = re.search(pattern, filename)
    if match:
        prompt_length = int(match.group(1))
        concurrency = int(match.group(2))
        return prompt_length, concurrency
    print(f"Warning: Could not extract parameters from filename: {filename}")
    return None

def collect_data(directory):
    """
    Scans the directory for log files, parses them, and returns the structured data.
    """
    all_data = []

    # Iterate over all files in the given directory
    for filename in os.listdir(directory):
        if filename.endswith(".log") and "prompt-" in filename and "concurrency-" in filename:
            params = extract_parameters_from_filename(filename)
            if not params:
                print(f"Skipping file (name format unrecognized): {filename}")
                continue

            prompt_length, concurrency = params
            metrics = parse_log_file(os.path.join(directory, filename))

            if metrics:
                if 'req_throughput' in metrics and prompt_length is not None:
                    metrics['prefill_throughput'] = metrics['req_throughput'] * prompt_length

                all_data.append({
                    'filename': filename,
                    'prompt_length': prompt_length,
                    'concurrency': concurrency,
                    **metrics
                })

    print(f"Found and processed {len(all_data)} log files in '{directory}'.")
    return all_data

def plot_latency(data, title, x_key, x_label, output_filename):
    """
    Plots the Mean TTFT and Mean ITL against a given x-axis metric using 
    a dual Y-axis (TTFT left, ITL right) and a logarithmic X-axis scale.
    """
    # Sort data based on the x_key for proper line plotting
    data.sort(key=lambda item: item[x_key])

    x_values = [item[x_key] for item in data]
    ttft_values = [item.get('ttft') for item in data]
    itl_values = [item.get('itl') for item in data]

    if not x_values:
        print(f"Warning: No data to plot for {title}. Skipping.")
        return

    fig, ax1 = plt.subplots(figsize=(10, 6))

    # --- Primary Y-axis (ax1) for TTFT (Left) ---
    color_ttft = '#3b82f6' # blue-500
    # Plot only if there's data
    line1, = ax1.plot(x_values, ttft_values, marker='o', linestyle='-', color=color_ttft, linewidth=2, label='Mean TTFT (ms)')
    ax1.set_xlabel(x_label, fontsize=12)
    ax1.set_ylabel('Mean TTFT (ms)', color=color_ttft, fontsize=12)
    ax1.tick_params(axis='y', labelcolor=color_ttft)
    
    # Apply Log Scale to X-axis
    ax1.set_xscale('log')
    # Ensure ticks are only at data points (important for discrete data on log scale)
    ax1.set_xticks(x_values)
    # Ensure x-axis labels are shown as numbers, not scientific notation (if possible)
    ax1.get_xaxis().set_major_formatter(plt.ScalarFormatter()) 
    ax1.tick_params(axis='x', which='major', labelsize=10)


    # --- Secondary Y-axis (ax2) for ITL (Right) ---
    ax2 = ax1.twinx()
    color_itl = '#10b981' # emerald-500
    line2, = ax2.plot(x_values, itl_values, marker='s', linestyle='--', color=color_itl, linewidth=2, label='Mean ITL (ms)')
    ax2.set_ylabel('Mean ITL (ms)', color=color_itl, fontsize=12)
    ax2.tick_params(axis='y', labelcolor=color_itl)
    
    # --- Final Plot Styling ---
    
    plt.title(title, fontsize=16, fontweight='bold')
    
    # Combine legends from both axes
    lines = [line1, line2]
    labels = [l.get_label() for l in lines]
    ax1.legend(lines, labels, loc='best', fontsize=10)
    
    # Grid applies to ax1 (the main plotting area)
    ax1.grid(True, linestyle=':', alpha=0.6)

    # Clean borders
    ax1.spines['top'].set_visible(False)
    ax2.spines['top'].set_visible(False)
    
    fig.tight_layout()
    plt.savefig(output_filename, dpi=300)
    print(f"Figure saved as {output_filename}")

def plot_throughput(data, title, x_key, x_label, output_filename):
    """
    Plots Request Throughput and Output Token Throughput against a given 
    x-axis metric using a dual Y-axis and a logarithmic X-axis scale.
    """
    data.sort(key=lambda item: item[x_key])

    x_values = [item[x_key] for item in data]
    prefill_tp_values = [item.get('prefill_throughput') for item in data]
    token_tp_values = [item.get('token_throughput') for item in data]

    if not x_values:
        print(f"Warning: No data to plot for {title}. Skipping.")
        return

    fig, ax1 = plt.subplots(figsize=(10, 6))

    # --- Primary Y-axis (ax1) for Prefill Throughput (Left) ---
    color_prefill = '#ef4444' # red-500
    line1, = ax1.plot(x_values, prefill_tp_values, marker='o', linestyle='-', color=color_prefill, linewidth=2, label='Prefill Throughput (tok/s)')
    ax1.set_xlabel(x_label, fontsize=12)
    ax1.set_ylabel('Prefill Throughput (tok/s)', color=color_prefill, fontsize=12)
    ax1.tick_params(axis='y', labelcolor=color_prefill)
    ax1.set_xscale('log')
    ax1.set_xticks(x_values)
    ax1.get_xaxis().set_major_formatter(plt.ScalarFormatter())
    ax1.tick_params(axis='x', which='major', labelsize=10)

    # --- Secondary Y-axis (ax2) for Output Token Throughput (Right) ---
    ax2 = ax1.twinx()
    color_output = '#f97316' # orange-500
    line2, = ax2.plot(x_values, token_tp_values, marker='s', linestyle='--', color=color_output, linewidth=2, label='Output Token Throughput (tok/s)')
    ax2.set_ylabel('Output Token Throughput (tok/s)', color=color_output, fontsize=12)
    ax2.tick_params(axis='y', labelcolor=color_output)
    
    # --- Final Plot Styling ---
    plt.title(title, fontsize=16, fontweight='bold')
    
    # Combine legends from both axes
    lines = [line1, line2]
    labels = [l.get_label() for l in lines]
    # Position legend to avoid overlap, e.g., 'upper left'
    ax1.legend(lines, labels, loc='upper left', fontsize=10)
    
    ax1.grid(True, linestyle=':', alpha=0.6)

    ax1.spines['top'].set_visible(False)
    ax2.spines['top'].set_visible(False)
    
    fig.tight_layout()
    plt.savefig(output_filename, dpi=300)
    print(f"Figure saved as {output_filename}")

def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(description="Generate plots from benchmark log files.")
    parser.add_argument(
        "--base-dir",
        type=str,
        default="bench_results",
        help="The base directory where benchmark results are stored."
    )
    parser.add_argument(
        "--model-name",
        type=str,
        default=None,
        help="The name of the model to include in plot titles."
    )
    args = parser.parse_args()

    # Check for matplotlib installation first
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("Error: The 'matplotlib' library is not installed.")
        print("Please install it using: pip install matplotlib")
        exit(1)

    if not os.path.isdir(args.base_dir):
        print(f"Error: Base directory '{args.base_dir}' not found. Did you run the benchmark script?")
        return

    # Walk through the results directory and generate plots for each sub-directory
    for subdir, _, _ in os.walk(args.base_dir):
        # We are interested in the leaf directories which contain the logs
        if subdir.endswith("prompt_sweep") or subdir.endswith("concurrency_sweep") or subdir.endswith("long_prompt_concurrency_sweep"):
            print(f"\n--- Processing results in: {subdir} ---")
            data = collect_data(subdir)
            if not data:
                continue

            # Extract plot title details from the path
            parts = subdir.replace(args.base_dir, '').strip(os.path.sep).split(os.path.sep)
            output_len_str = parts[0].replace('_', ' ')
            sweep_type = "Max Concurrency" if "concurrency" in subdir else "Input Length"
            x_key = "concurrency" if "concurrency_sweep" in subdir else "prompt_length"
            x_label = f'{sweep_type} (Tokens)' if x_key == 'prompt_length' else sweep_type

            model_str = f" for {args.model_name}" if args.model_name else ""

            # Add prompt length to title for concurrency sweeps
            if "concurrency" in subdir and data:
                prompt_len = data[0].get('prompt_length')
                details_str = f"(Prompt {prompt_len}, {output_len_str})"
            else:
                details_str = f"({output_len_str})"

            # Generate Latency Plot
            latency_title = f'Latency vs. {sweep_type}{model_str} {details_str}'
            latency_filename = os.path.join(subdir, 'latency_plot.png')
            plot_latency(data, latency_title, x_key, x_label, latency_filename)

            # Generate Throughput Plot
            throughput_title = f'Throughput vs. {sweep_type}{model_str} {details_str}'
            throughput_filename = os.path.join(subdir, 'throughput_plot.png')
            plot_throughput(data, throughput_title, x_key, x_label, throughput_filename)

if __name__ == "__main__":
    main()
