#!/usr/bin/env python3

# Shebang line
#
# Tells Unix/Linux/macOS systems:
# "Run this script using python3 found in the system PATH"
#
# This allows execution like:
# ./build_package.py
#
# On Windows this line is ignored.

"""
Cross-platform Lambda deployment package creator using uv.
Works on Windows, Mac, and Linux.
"""

# Multi-line module documentation string (docstring)
#
# Explains purpose of script:
# - Creates AWS Lambda deployment ZIP package
# - Uses dependencies installed via uv
# - Works across operating systems

# =========================
# IMPORTS
# =========================

import os

# Built-in OS utilities
#
# Used here for:
# - removing files
# - walking directory trees
# - filesystem operations

import sys

# Provides access to:
# - command line args
# - exiting program with status codes
#
# Used here for:
# sys.exit(1)

import shutil

# High-level file operations
#
# Used for:
# - copying directories
# - deleting directories
# - copying files

import zipfile

# Built-in ZIP archive creation/extraction module
#
# Used to create Lambda deployment ZIP

from pathlib import Path

# Modern object-oriented filesystem path library
#
# Better than using raw strings
#
# Example:
# Path("folder/file.txt")

# =========================
# MAIN FUNCTION
# =========================

def create_deployment_package():

    """
    Create a Lambda deployment package with dependencies from uv.
    """

    # Main function responsible for:
    #
    # 1. Finding Python dependencies
    # 2. Copying them into temporary build directory
    # 3. Copying Lambda handler files
    # 4. Creating deployment ZIP
    # 5. Cleaning up temporary files

    # =========================
    # PATH SETUP
    # =========================

    # Directory where THIS script exists
    #
    # __file__ = current Python file path
    #
    # Example:
    # /project/build_lambda.py
    #
    # .parent gives:
    # /project
    current_dir = Path(__file__).parent

    # Temporary build directory
    #
    # Example:
    # /project/build
    build_dir = current_dir / 'build'

    # Directory containing final deployment contents before zipping
    #
    # Example:
    # /project/build/package
    package_dir = build_dir / 'package'

    # Final Lambda deployment ZIP file path
    #
    # Example:
    # /project/lambda_function.zip
    zip_path = current_dir / 'lambda_function.zip'

    # Path to virtual environment libraries
    #
    # uv creates .venv directory
    #
    # Linux/macOS:
    # .venv/lib/python3.x/site-packages
    #
    # Windows structure differs slightly
    #
    # rglob later helps find actual site-packages folder
    venv_site_packages = current_dir / '.venv' / 'lib'

    # =========================
    # CLEAN OLD BUILDS
    # =========================

    # Remove previous temporary build directory
    #
    # Prevents stale files from previous builds
    if build_dir.exists():
        shutil.rmtree(build_dir)

    # Remove old deployment ZIP if it exists
    if zip_path.exists():
        os.remove(zip_path)

    # =========================
    # CREATE BUILD DIRECTORY
    # =========================

    # Create package directory recursively
    #
    # parents=True:
    # Creates parent directories automatically
    #
    # exist_ok=True:
    # Avoids error if directory already exists
    package_dir.mkdir(parents=True, exist_ok=True)

    # =========================
    # FIND SITE-PACKAGES
    # =========================

    # site-packages contains installed Python libraries
    #
    # Example:
    # boto3
    # requests
    # sentence_transformers
    #
    # Lambda deployment package MUST include these dependencies

    site_packages = None

    # rglob recursively searches directories
    #
    # Searches entire .venv/lib tree for folder named site-packages
    #
    # Cross-platform friendly
    for path in venv_site_packages.rglob('site-packages'):

        # Save first matching path
        site_packages = path

        # Stop searching after first match
        break

    # =========================
    # VALIDATE DEPENDENCIES
    # =========================

    # Ensure site-packages was found
    #
    # If not:
    # - dependencies probably not installed
    # - uv init / uv add may not have been run
    if not site_packages or not site_packages.exists():

        print(
            "Error: Could not find site-packages. "
            "Make sure you've run 'uv init' and "
            "'uv add' for dependencies."
        )

        # Exit with non-zero status code
        #
        # Convention:
        # 0 = success
        # non-zero = error
        sys.exit(1)

    # Informational logging
    print(f"Copying dependencies from {site_packages}...")

    # =========================
    # COPY DEPENDENCIES
    # =========================

    # Iterate through everything inside site-packages
    for item in site_packages.iterdir():

        # Skip metadata directories
        #
        # .dist-info contains package metadata
        # not required at runtime in Lambda
        #
        # __pycache__ contains compiled bytecode
        # unnecessary for deployment
        if item.name.endswith('.dist-info') or item.name == '__pycache__':
            continue

        # If dependency is a directory/package
        if item.is_dir():

            # Copy entire package directory
            #
            # dirs_exist_ok=True prevents errors if folder exists
            shutil.copytree(
                item,
                package_dir / item.name,
                dirs_exist_ok=True
            )

        else:
            # Copy single files
            #
            # Example:
            # standalone .py files
            shutil.copy2(item, package_dir)

    # =========================
    # COPY LAMBDA HANDLER FILES
    # =========================

    print("Copying Lambda function code...")

    # Copy ingest Lambda handler if present
    #
    # Handler example:
    # ingest_s3vectors.lambda_handler
    if (current_dir / 'ingest_s3vectors.py').exists():

        shutil.copy(
            current_dir / 'ingest_s3vectors.py',
            package_dir
        )

    # Copy search Lambda handler if present
    if (current_dir / 'search_s3vectors.py').exists():

        shutil.copy(
            current_dir / 'search_s3vectors.py',
            package_dir
        )

    # =========================
    # CREATE ZIP FILE
    # =========================

    print("Creating deployment package...")

    # Open ZIP file in write mode
    #
    # ZIP_DEFLATED enables compression
    with zipfile.ZipFile(
        zip_path,
        'w',
        zipfile.ZIP_DEFLATED
    ) as zipf:

        # Walk entire package directory recursively
        for root, dirs, files in os.walk(package_dir):

            # Remove __pycache__ directories from traversal
            #
            # Modifying dirs in-place affects os.walk behavior
            dirs[:] = [
                d for d in dirs
                if d != '__pycache__'
            ]

            # Process each file
            for file in files:

                # Skip compiled Python files
                #
                # .pyc files unnecessary for Lambda deployment
                if file.endswith('.pyc'):
                    continue

                # Full filesystem path
                file_path = Path(root) / file

                # Relative path INSIDE ZIP archive
                #
                # Example:
                # boto3/session.py
                #
                # instead of:
                # /tmp/build/package/boto3/session.py
                arcname = file_path.relative_to(package_dir)

                # Add file to ZIP
                zipf.write(file_path, arcname)

    # =========================
    # CLEAN TEMP FILES
    # =========================

    # Remove temporary build directory after ZIP creation
    #
    # Final artifact remains:
    # lambda_function.zip
    shutil.rmtree(build_dir)

    # =========================
    # REPORT PACKAGE SIZE
    # =========================

    # Get ZIP file size in MB
    size_mb = zip_path.stat().st_size / (1024 * 1024)

    print(f"\n✅ Deployment package created: {zip_path}")

    print(f"   Size: {size_mb:.2f} MB")

    # AWS Lambda ZIP deployment limit warning
    #
    # Lambda direct upload limit:
    # 50 MB compressed
    if size_mb > 50:

        print(
            "⚠️  Warning: Package exceeds 50MB. "
            "Consider using Lambda Layers."
        )

    # Return ZIP file path as string
    return str(zip_path)

# =========================
# ENTRY POINT
# =========================

# This condition checks:
# "Is this file being run directly?"
#
# If YES:
# execute create_deployment_package()
#
# If imported as module:
# do NOT execute automatically
#
# Example:
#
# Direct execution:
# python build.py
#
# Imported:
# import build
if __name__ == '__main__':

    create_deployment_package()