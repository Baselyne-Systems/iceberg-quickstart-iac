"""Dagster op that invokes Soda scan as a subprocess."""

import subprocess
from pathlib import Path

from dagster import OpExecutionContext, op

SODA_CHECKS_DIR = Path(__file__).parent / "soda_checks"


@op
def run_soda_scan(context: OpExecutionContext, check_file: str) -> dict:
    """Run a Soda scan against a check file.

    Args:
        check_file: Name of the YAML check file in soda_checks/ directory.

    Returns:
        Dict with scan results including pass/fail status.
    """
    check_path = SODA_CHECKS_DIR / check_file

    if not check_path.exists():
        raise FileNotFoundError(f"Soda check file not found: {check_path}")

    context.log.info("Running Soda scan: %s", check_path)

    # Soda configuration.yaml must be generated from Terraform outputs at deploy time
    config_path = SODA_CHECKS_DIR.parent / "configuration.yaml"

    cmd = [
        "soda", "scan",
        "-d", "lakehouse",
        "-c", str(config_path),
        str(check_path),
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)  # noqa: S603

    context.log.info("Soda stdout:\n%s", result.stdout)
    if result.stderr:
        context.log.warning("Soda stderr:\n%s", result.stderr)

    scan_passed = result.returncode == 0

    if not scan_passed:
        context.log.error("Soda scan FAILED for %s", check_file)

    return {
        "check_file": check_file,
        "passed": scan_passed,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
