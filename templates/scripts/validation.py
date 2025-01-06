import sys

def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Invalid Python version {sys.version_info}, must be 3.11 or higher")


def validate() -> None:
    validate_python_version()
