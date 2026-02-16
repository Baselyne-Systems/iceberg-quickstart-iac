"""Dagster op that invokes Soda scan as a subprocess."""

import subprocess
from pathlib import Path

from dagster import Failure, OpExecutionContext, op

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

    # Soda configuration.yaml must be generated from Terraform outputs at deploy time
    config_path = SODA_CHECKS_DIR.parent / "configuration.yaml"

    if not config_path.exists():
        raise FileNotFoundError(
            f"Soda configuration not found at {config_path}. "
            "Generate it from Terraform outputs before running quality checks."
        )

    context.log.info("Running Soda scan: %s", check_path)

    cmd = [
        "soda",
        "scan",
        "-d",
        "lakehouse",
        "-c",
        str(config_path),
        str(check_path),
    ]

    try:
        result = subprocess.run(  # noqa: S603
            cmd, capture_output=True, text=True, timeout=300
        )
    except subprocess.TimeoutExpired as e:
        raise Failure(
            description=f"Soda scan timed out after 300s for {check_file}",
        ) from e

    context.log.info("Soda stdout:\n%s", result.stdout)
    if result.stderr:
        context.log.warning("Soda stderr:\n%s", result.stderr)

    scan_passed = result.returncode == 0

    if not scan_passed:
        raise Failure(
            description=f"Soda scan FAILED for {check_file}",
            metadata={
                "check_file": check_file,
                "returncode": result.returncode,
                "stdout": result.stdout[-2000:],
                "stderr": result.stderr[-2000:],
            },
        )

    return {
        "check_file": check_file,
        "passed": scan_passed,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
