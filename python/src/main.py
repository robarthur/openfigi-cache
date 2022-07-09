import os
import requests

def lambda_handler(event, context):
    API_KEY = os.getenv('API_KEY')

    if not API_KEY:
        raise ValueError('API_KEY environment variable is not set')

    message = f'API_KEY: {API_KEY}'  
    return { 
        'message' : message
    }