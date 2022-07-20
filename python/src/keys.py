import http
import os
import json
import boto3
import redis


def lambda_handler(event, context):
    REDIS_ENDPOINT = os.getenv("REDIS_ENDPOINT") or "localhost"
    REDIS_PORT = os.getenv("REDIS_PORT") or "6379"
    MAPPING_V3_API = "https://api.openfigi.com/v3/mapping"
    USE_SSL = False

    print(f"{REDIS_ENDPOINT=}, {REDIS_PORT=}, {USE_SSL=}")
    r = redis.Redis(
        host=REDIS_ENDPOINT,
        port=REDIS_PORT,
        charset="utf-8",
        decode_responses=True,
        socket_connect_timeout=2,
    )

    http_method = event.get("httpMethod")
    key = None
    pathParameters = event.get("pathParameters")
    if pathParameters:
        key = pathParameters.get("key")
    print(f"{http_method=}, {key=}")

    status_code = 200

    if http_method == "GET" and key:
        result = get_key(r, key)
    elif http_method == "GET" and not key:
        result = json.dumps(get_keys(r))
    elif http_method == "DELETE" and key:
        result = delete_key(r, key)
    elif http_method == "DELETE" and not key:
        result = json.dumps(delete_keys(r))
    else:
        status_code = 400
        result = "Invalid request"

    return {
        "isBase64Encoded": False,
        "statusCode": status_code,
        "body": result
    }

def get_key(r, key):
    print(f"fetching key: {key}")
    return r.get(key)

def get_keys(r):
    print("fetching all keys")
    return r.keys()

def delete_key(r, key):
    print(f"deleting key: {key}")
    return r.delete(key)

def delete_keys(r):
    print("deleting all keys")
    return r.flushdb()