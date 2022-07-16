import os
import json
import boto3
import requests
import redis

def lambda_handler(event, context):
    API_KEY = os.getenv('API_KEY')
    LOCAL_DDB_ENDPOINT =  'http://localhost:8000'
    MAPPING_V3_API='https://api.openfigi.com/v3/mapping'

    if not API_KEY:
        raise ValueError('API_KEY environment variable is not set')

    r = redis.Redis(charset="utf-8", decode_responses=True)
    keys = get_cache_keys_from_event(event)

    # Get as much as we can from cache
    #cache_result = [json.loads(k) for k in r.mget(keys) if k ]
    cache_result = [ json.loads(k) if k else None for k in r.mget(keys) ]

    print(f"{cache_result =}")
    cache_misses = get_cache_misses(cache_result, event)
    print(f"{cache_misses =}")

    response_json = []
    # Get everything else from API
    if cache_misses:
        headers={}
        headers.update({'X-OPENFIGI-KEY': API_KEY})
        response = requests.post(MAPPING_V3_API, headers=headers, json=cache_misses)
        if response.status_code == 200:
            response_json = response.json()
            # Store new data in cache
            cache_miss_keys = get_cache_keys_from_event(cache_misses)
            for i in zip(cache_miss_keys, response_json):
                r.set(i[0], json.dumps(i[1]))

    # Concatentate the results
    cache_result.extend(response_json)

    return cache_result

def get_cache_misses(cache_result, event):
    cache_misses = []
    if None in cache_result:
        empty_cache_result_indexes = [i for i, x in enumerate(cache_result) if x==None]
        cache_misses = [event[i] for i in empty_cache_result_indexes]
    return cache_misses

def get_cache_keys_from_event(event):
    return [ f"{d['idType']}_{d['idValue']}" for d in event ]