#!/bin/bash

# Define the path to the Cargo.toml file
cargo_file="$HOME/Documents/GitHub/GyroflowToolbox/Source/Frameworks/gyroflow/Cargo.toml"

# Extract the rev value for gyroflow-core
rev=$(grep 'gyroflow-core' $cargo_file | grep 'rev' | cut -d '"' -f 4)

# Check if the rev value is extracted
if [ -z "$rev" ]; then
    echo "Failed to extract rev value from Cargo.toml"
    exit 1
fi

# Define source and destination directories
source_dir="$HOME/.cargo/git/checkouts/gyroflow-e2875b874191d028/$rev/resources/camera_presets"
destination_dir="$HOME/Documents/GitHub/GyroflowToolbox/Source/Gyroflow/Plugin/Resources/Lens Profiles"

# Copy the contents, replacing any existing files and folders
cp -R "$source_dir"/* "$destination_dir"

# Check if the copy operation was successful
if [ $? -eq 0 ]; then
    echo "Files copied successfully."
else
    echo "Failed to copy files."
fi