import os
import wandb

api_key = "insert_your_api_key_here"

# 1. Set API key as environment variable so wandb picks it up
os.environ["WANDB_API_KEY"] = api_key

# 2. Login silently
wandb.login(key=api_key, relogin=True)