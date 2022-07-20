import os
import json
import boto3
import requests
import redis


def lambda_handler(event, context):
    API_KEY = os.getenv("API_KEY")
    REDIS_ENDPOINT = os.getenv("REDIS_ENDPOINT") or "localhost"
    REDIS_PORT = os.getenv("REDIS_PORT") or "6379"
    MAPPING_V3_API = "https://api.openfigi.com/v3/mapping"
    USE_SSL = False

    body = json.loads(event.get("body"))

    if not API_KEY:
        raise ValueError("API_KEY environment variable is not set")

    print(f"{REDIS_ENDPOINT=}, {REDIS_PORT=}, {USE_SSL=}")
    print(f"{body=}")
    r = redis.Redis(
        host=REDIS_ENDPOINT,
        port=REDIS_PORT,
        charset="utf-8",
        decode_responses=True,
        socket_connect_timeout=2,
    )
    keys = get_cache_keys_from_body(body)

    # Get as much as we can from cache
    # cache_result = [json.loads(k) for k in r.mget(keys) if k ]
    cache_result = [json.loads(k) if k else None for k in r.mget(keys)]

    print(f"{cache_result =}")
    cache_misses = get_cache_misses(cache_result, body)
    print(f"{cache_misses =}")

    response_json = []
    # Get everything else from API
    if cache_misses:
        headers = {}
        headers.update({"X-OPENFIGI-APIKEY": API_KEY})
        print(f"Making request to open figi API: {headers=}, {cache_misses=}")
        response = requests.post(MAPPING_V3_API, headers=headers, json=cache_misses)
        print(f"response code={response.status_code}")
        if response.status_code == 200:
            response_json = response.json()
            # Store new data in cache}
            cache_miss_keys = get_cache_keys_from_body(cache_misses)
            print(f"{cache_miss_keys =}")

            for i in zip(cache_miss_keys, response_json):
                print(f"setting key: {i[0]} with value: {i[1]}")
                r.set(i[0], json.dumps(i[1]))

    # Concatentate the results and drop Nones
    cache_result = list(filter(None, cache_result))
    cache_result.extend(response_json)

    return {"isBase64Encoded": False, "statusCode": 200, "body": json.dumps(cache_result)}


def get_cache_misses(cache_result, body):
    cache_misses = []
    if None in cache_result:
        empty_cache_result_indexes = [
            i for i, x in enumerate(cache_result) if x == None
        ]
        cache_misses = [body[i] for i in empty_cache_result_indexes]
    return cache_misses


def get_cache_keys_from_body(body):
    return [f"{d['idType']}_{d['idValue']}" for d in body]
