import json
import os
from decimal import Decimal

import boto3

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": os.environ.get("CORS_ORIGIN", "*"),
}


def _resp(code, body):
    return {"statusCode": code, "headers": HEADERS, "body": json.dumps(body)}


def lambda_handler(event, context):
    try:
        payload = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _resp(400, {"error": "Invalid JSON"})

    account_id = payload.get("accountId")
    if not account_id:
        return _resp(400, {"error": "accountId is required"})

    item = table.get_item(Key={"account_id": str(account_id)}).get("Item")
    if not item:
        return _resp(404, {"error": "Account not found"})

    balance = item["balance"]
    if isinstance(balance, Decimal):
        balance = float(balance)
    return _resp(200, {"accountId": account_id, "balance": balance})
