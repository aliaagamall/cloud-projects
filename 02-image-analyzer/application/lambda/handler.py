import base64
import binascii
import json
import os

import boto3


rekognition = boto3.client(
    "rekognition",
    region_name=os.environ.get("AWS_REGION")
)


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }


def lambda_handler(event, context):
    try:
        body = event.get("body")

        if not body:
            return response(
                400,
                {
                    "error": "Request body is required."
                }
            )

        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode("utf-8")

        payload = json.loads(body)

        image_base64 = payload.get("image")

        if not image_base64:
            return response(
                400,
                {
                    "error": "The 'image' field is required."
                }
            )

        try:
            image_bytes = base64.b64decode(
                image_base64,
                validate=True
            )
        except (binascii.Error, ValueError):
            return response(
                400,
                {
                    "error": "The image must be valid Base64."
                }
            )

        if not image_bytes:
            return response(
                400,
                {
                    "error": "The image cannot be empty."
                }
            )

        result = rekognition.detect_faces(
            Image={
                "Bytes": image_bytes
            },
            Attributes=["ALL"]
        )

        faces = result.get("FaceDetails", [])

        if len(faces) != 1:
            return response(
                200,
                {
                    "friendly": False,
                    "reason": "exactly_one_face_required",
                    "face_count": len(faces)
                }
            )

        face = faces[0]

        smile = face.get("Smile", {})
        eyes_open = face.get("EyesOpen", {})

        is_smiling = smile.get("Value", False)
        are_eyes_open = eyes_open.get("Value", False)

        friendly = is_smiling and are_eyes_open

        reason = "friendly"

        if not is_smiling:
            reason = "not_smiling"
        elif not are_eyes_open:
            reason = "eyes_not_open"

        return response(
            200,
            {
                "friendly": friendly,
                "reason": reason,
                "face_count": 1,
                "smiling": is_smiling,
                "eyes_open": are_eyes_open
            }
        )

    except json.JSONDecodeError:
        return response(
            400,
            {
                "error": "Request body must contain valid JSON."
            }
        )

    except Exception as exc:
        print(f"Image analysis failed: {exc}")

        return response(
            500,
            {
                "error": "Internal server error."
            }
        )