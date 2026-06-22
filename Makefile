.PHONY: api bot

VENV := venv

api:
	$(VENV)/bin/uvicorn app:app --reload

bot:
	$(VENV)/bin/python bot.py
