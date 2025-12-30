from app import app

# Vercel needs a file named index.py or similar in /api
# This bridges the root app.py to Vercel's expected structure
export_app = app
