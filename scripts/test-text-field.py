#!/usr/bin/env python3
"""Run the production text-field coordinator in isolation; no lights are contacted."""
from pathlib import Path
import os
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
source = (project / "Sources/Lumos/ContentView.swift").read_text()
start = source.index("private struct ValidatedTextField:")
end = source.index("private struct ColorComponentSlider:", start)
harness = (project / "Tests/ValidatedTextFieldRegression.swift").read_text()
sdk = os.environ.get("SDKROOT")
if not sdk:
    sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="lumos-field-tests-") as directory:
    root = Path(directory)
    combined = root / "Regression.swift"
    combined.write_text(source[start:end] + "\n" + harness)
    binary = root / "Regression"
    subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6",
                    "-sdk", sdk, "-module-cache-path", str(root / "modules"),
                    str(combined), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
