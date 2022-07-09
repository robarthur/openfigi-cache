import os
import requests

def lambda_handler(event, context):
    API_KEY = os.getenv('API_KEY')

    if not API_KEY:
        raise ValueError('API_KEY environment variable is not set')

    MAPPING_V3_API='https://api.openfigi.com/v3/mapping'
    headers={}
    headers.update({'X-OPENFIGI-KEY': API_KEY})

    response = requests.post(MAPPING_V3_API, headers=headers, json=event)

    return { 
        'response' : response.json()
    }