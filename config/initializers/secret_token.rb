# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
#
# Be sure to restart your server when you modify this file.
#
# Your secret key for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!
#
# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.
# You can use `rake secret` to generate a secure secret key.
#
# Make sure your secret_key_base is kept private
# if you're sharing your code publicly.
#
# Although this is not needed for an api-only application, rails4
# requires secret_key_base or secret_token to be defined, otherwise an
# error is raised.
# Using secret_token for rails3 compatibility. Change to secret_key_base
# to avoid deprecation warning.
# Can be safely removed in a rails3 api-only application.
Zax::Application.config.secret_token = '4767df3b7f81eb616dad6038d4ae20a1a0ec5c2b4e534c5de5d4d6ba62bbc9ceefcd1254f51c3e9c77b2375d9638879398e8b37e9a0d266a85804268498b3c82'