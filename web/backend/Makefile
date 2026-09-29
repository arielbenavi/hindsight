.PHONY: api bot web

VENV := venv

api:
	$(VENV)/bin/uvicorn app:app --reload

bot:
	$(VENV)/bin/python bot.py

web:
	cd ../frontend && npm run dev
