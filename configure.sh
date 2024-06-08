#!/bin/bash
set -e

bundle config --local path '.bundle/vendor'
bundle config 
bundle install

bundle exec pod install --repo-update
