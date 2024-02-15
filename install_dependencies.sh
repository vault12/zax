#!/bin/bash

# Run bundle install
bundle install

# Run npm install
npm install

# Clear public folder
rm -rf public

# Populate public folder with the necessary files
cp -a node_modules/zax-dashboard/dist/. public/
