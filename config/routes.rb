# Copyright (c) 2015 Vault12, Inc.
# MIT License https://opensource.org/licenses/MIT
Rails.application.routes.draw do

  # Establish token session
  post    'start_session'   => 'session#start_session_token'
  post    'verify_session'   => 'session#verify_session_token'

  # Prove ownership of hashed public key (hpk)
  post    'prove'  => 'proof#prove_hpk'

  # issue commands for mailbox of given hpk
  post    'command' => 'command#process_cmd'

  # receive file upload from nginx-upload-module
  # match 'upload_complete', to: 'command#upload_preflight', via: [:options, :get]
  # post  'upload_complete' => 'command#upload_complete'

  match "*path", to: "session#missing_route", via: :all
end
