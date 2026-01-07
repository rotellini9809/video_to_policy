import os
import wandb

api_key = "2afebd919c3c3e82e91783cae9df8ee5de971b6f"

# 1. Set API key as environment variable so wandb picks it up
os.environ["WANDB_API_KEY"] = api_key

# 2. Login silently
wandb.login(key=api_key, relogin=True)