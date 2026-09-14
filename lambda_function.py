import json
import os
import base64
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')

TABLE_NAME = os.environ['DB_TABLE']
RECEIVER_EMAIL = os.environ['RECEIVER_EMAIL']
SENDER_EMAIL = os.environ['SENDER_EMAIL']

def lambda_handler(event, context):
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,POST'
    }

    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': cors_headers, 'body': json.dumps({'message': 'Preflight passed'})}

    try:
        raw_body = event.get('body') or '{}'
        if event.get('isBase64Encoded'):
            raw_body = base64.b64decode(raw_body).decode('utf-8')
        body = json.loads(raw_body)
        name = str(body.get('name', '')).strip()
        email = str(body.get('email', '')).strip().lower()
        sector = str(body.get('sector', '')).strip()
        message = str(body.get('message', '')).strip()
        timestamp = datetime.now(timezone.utc).isoformat()

        if not name or not email or not sector or not message:
            return {'statusCode': 400, 'headers': cors_headers, 'body': json.dumps({'error': 'Name, email, sector, and message are required'})}

        # 1. Commit record details directly to Amazon DynamoDB Ledger storage
        table = dynamodb.Table(TABLE_NAME)
        table.put_item(
            Item={
                'email': email,
                'timestamp': timestamp,
                'name': name,
                'sector': sector,
                'message': message
            }
        )

        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={'ToAddresses': [RECEIVER_EMAIL]},
            ReplyToAddresses=[email],
            Message={
                'Subject': {'Data': f'Aseecrox inquiry: {sector}', 'Charset': 'UTF-8'},
                'Body': {'Text': {'Data': f'New inquiry from {name} ({email})\\n\\nSector: {sector}\\n\\n{message}', 'Charset': 'UTF-8'}}
            }
        )

        return {'statusCode': 200, 'headers': cors_headers, 'body': json.dumps({'status': 'success'})}

    except Exception as e:
        print(f"CRITICAL DISPATCH ERROR: {str(e)}")
        return {'statusCode': 500, 'headers': cors_headers, 'body': json.dumps({'error': str(e)})}