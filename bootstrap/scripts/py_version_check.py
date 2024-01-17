import sys

required_version = (3, 11, 0)

if sys.version_info >= required_version:
    print(f"Python version is greater than or equal to 3.11")
else:
    print("Python version is below 3.11. Please upgrade.")
    exit(1)
