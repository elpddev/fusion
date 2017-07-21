use Mix.Config
                                        
config :dockerex,                       
  #host: "https://10.10.10.1:2376/",
  host: "http+unix://%2Fvar%2Frun%2Fdocker.sock/",
  options: [                            
  #  ssl:  [
  #    {:certfile, "/path/to/your/cert.pem"},
  #    {:keyfile, "/path/to/your/key.pem"}
  #  ]
  ]
