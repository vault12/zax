Rails.application.routes.draw do

  # Establish token session
  post    'start_session'   => 'session#start_session_token'
  post    'verify_session'   => 'session#verify_session_token'

  # Prove ownership of hashed public key (hpk)
  post    'prove'  => 'proof#prove_hpk'

  # command controller functions
  post    'command' => 'command#process_cmd'
end
