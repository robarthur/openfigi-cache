import os
import boto3
import requests

def lambda_handler(event, context):
    API_KEY = os.getenv('API_KEY')
    LOCAL_DDB_ENDPOINT =  'http://localhost:8000'
    MAPPING_V3_API='https://api.openfigi.com/v3/mapping'

    if not API_KEY:
        raise ValueError('API_KEY environment variable is not set')

    ddb = boto3.resource('dynamodb')

    if os.getenv("IS_LOCAL"):
        print(f"Running locally.  Use local dynamodb {LOCAL_DDB_ENDPOINT}")
        ddb = boto3.resource('dynamodb', endpoint_url=LOCAL_DDB_ENDPOINT)
   
    table = ddb.Table('MappingsV3')

    headers={}
    headers.update({'X-OPENFIGI-KEY': API_KEY})

    response = requests.post(MAPPING_V3_API, headers=headers, json=event)

    if response.status_code == 200:
        response_json = response.json()

        data = []
        for i in zip(event, response_json):
            id = "_".join(i[0].values())
            data = i[1]['data']
            data = [dict(item, id=id) for item in data]

        with table.batch_writer() as writer:
            for item in data:
                writer.put_item(Item=item)

    return { 
        'response' : response.status_code
    }