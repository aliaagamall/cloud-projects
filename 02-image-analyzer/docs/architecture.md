# Image Analyzer Architecture

## 1. Architecture Overview

The Image Analyzer uses a serverless architecture to expose an image-analysis API to existing applications.

A consuming application submits an image encoded as Base64 through an HTTPS POST request.

The request is received by Amazon API Gateway and forwarded to an AWS Lambda function.

Lambda validates and decodes the image, then calls Amazon Rekognition `DetectFaces`.

Rekognition analyzes the image and returns facial attributes.

Lambda evaluates the response and returns a structured classification to the consuming application.

No persistent storage is used for submitted images.

---

## 2. High-Level Architecture

```mermaid
flowchart LR
    CLIENT[Existing Applications]

    APIGW[Amazon API Gateway<br/>POST /friendly]

    LAMBDA[AWS Lambda<br/>Python]

    REK[Amazon Rekognition<br/>DetectFaces]

    CW[Amazon CloudWatch Logs]

    CLIENT -->|HTTPS POST<br/>Base64 Image| APIGW
    APIGW -->|Invoke| LAMBDA
    LAMBDA -->|DetectFaces| REK
    REK -->|Facial Attributes| LAMBDA
    LAMBDA -->|Classification Response| APIGW
    APIGW -->|HTTPS Response| CLIENT

    LAMBDA -->|Logs| CW
```

---

## 3. Request and Response Flow

```mermaid
sequenceDiagram
    participant Client as Consuming Application
    participant API as API Gateway
    participant Lambda as Lambda
    participant Rekognition as Amazon Rekognition

    Client->>API: POST /friendly<br/>Base64 image
    API->>Lambda: Invoke function
    Lambda->>Lambda: Validate request
    Lambda->>Lambda: Decode image
    Lambda->>Rekognition: DetectFaces
    Rekognition-->>Lambda: Face attributes
    Lambda->>Lambda: Evaluate photo
    Lambda-->>API: Structured result
    API-->>Client: HTTPS response
```

---

## 4. Application Decision Flow

The Lambda function applies the business rules after receiving the Rekognition response.

```mermaid
flowchart TD
    START[Receive Image] --> VALIDATE[Validate Request]
    VALIDATE --> DECODE[Decode Base64 Image]
    DECODE --> DETECT[Rekognition DetectFaces]

    DETECT --> FACES{Exactly One Face?}

    FACES -->|No| BAD1[Bad Profile Photo]
    FACES -->|Yes| SMILE{Smiling?}

    SMILE -->|No| BAD2[Bad Profile Photo]
    SMILE -->|Yes| EYES{Eyes Open?}

    EYES -->|No| BAD3[Bad Profile Photo]
    EYES -->|Yes| GOOD[Good Profile Photo]
```

---

## 5. Requirements-to-Architecture Mapping

```mermaid
flowchart TD
    subgraph Requirements
        R1[Analyze Profile Photos]
        R2[Integrate With Applications]
        R3[Support PNG and JPEG]
        R4[High Availability]
        R5[Low Cost]
        R6[Scalability]
        R7[No Image Persistence]
        R8[Infrastructure as Code]
    end

    subgraph Capabilities
        C1[ML Image Analysis]
        C2[HTTPS API]
        C3[Image Validation]
        C4[Serverless Execution]
        C5[Managed Scaling]
        C6[In-Memory Processing]
        C7[Infrastructure Automation]
    end

    subgraph AWS_Services
        S1[Amazon Rekognition]
        S2[Amazon API Gateway]
        S3[AWS Lambda]
        S4[Terraform]
        S5[CloudWatch Logs]
    end

    R1 --> C1
    R2 --> C2
    R3 --> C3
    R4 --> C4
    R5 --> C4
    R6 --> C5
    R7 --> C6
    R8 --> C7

    C1 --> S1
    C2 --> S2
    C3 --> S3
    C4 --> S2
    C4 --> S3
    C5 --> S2
    C5 --> S3
    C6 --> S3
    C7 --> S4

    S3 --> S5
```

---

## 6. AWS Service Responsibilities

### Amazon API Gateway

API Gateway provides the public HTTPS interface for consuming applications.

Responsibilities:

- Expose the API endpoint.
- Receive POST requests.
- Route requests to Lambda.
- Return Lambda responses to clients.

Initial API:

```text
POST /friendly
```

---

### AWS Lambda

Lambda contains the application logic.

Responsibilities:

- Validate the incoming request.
- Decode Base64 image data.
- Call Rekognition.
- Evaluate facial attributes.
- Generate the final classification.
- Return a structured response.
- Produce application logs.

Lambda does not persist submitted images.

---

### Amazon Rekognition

Rekognition provides the managed ML capability.

The application uses:

```text
DetectFaces
```

The response is used to evaluate:

- Number of detected faces.
- Smile status.
- Eyes-open status.

Rekognition is used instead of developing and hosting a custom computer-vision model.

---

### Amazon CloudWatch

CloudWatch Logs receives Lambda execution logs.

This provides visibility into:

- Function execution.
- Errors.
- Debugging information.
- Operational behavior.

---

## 7. Security Architecture

```mermaid
flowchart LR
    CLIENT[Consuming Application]
    HTTPS[HTTPS]
    API[API Gateway]
    ROLE[Lambda Execution Role]
    LAMBDA[Lambda]
    REK[Amazon Rekognition]
    LOGS[CloudWatch Logs]

    CLIENT --> HTTPS
    HTTPS --> API
    API --> LAMBDA

    ROLE -.->|Least-Privilege Permissions| LAMBDA

    LAMBDA -->|DetectFaces| REK
    LAMBDA -->|Execution Logs| LOGS
```

Security principles:

- Client communication uses HTTPS.
- Client applications do not receive AWS credentials.
- Lambda accesses Rekognition through its IAM execution role.
- The Lambda role uses least-privilege permissions.
- Images are not persisted.
- CloudWatch provides operational visibility.

---

## 8. Data Flow

```mermaid
flowchart LR
    IMAGE[Image File]
    BASE64[Base64 Encoding]
    REQUEST[HTTPS Request]
    API[API Gateway]
    MEMORY[Lambda Memory]
    REK[Amazon Rekognition]
    RESULT[Classification]
    RESPONSE[HTTPS Response]

    IMAGE --> BASE64
    BASE64 --> REQUEST
    REQUEST --> API
    API --> MEMORY
    MEMORY --> REK
    REK --> RESULT
    RESULT --> MEMORY
    MEMORY --> RESPONSE
```

There is intentionally no S3, database, or other persistent storage component in the image data path.

---

## 9. Terraform Architecture

Terraform provisions the infrastructure required by the application.

```mermaid
flowchart TD
    V[versions.tf]
    B[backend.tf]
    VAR[variables.tf]
    M[main.tf]

    IAM[iam.tf]
    LAMBDA[lambda.tf]
    API[apigateway.tf]
    OUT[outputs.tf]

    V --> CONFIG[Terraform Configuration]
    B --> CONFIG
    VAR --> CONFIG
    M --> CONFIG

    CONFIG --> IAM
    CONFIG --> LAMBDA
    CONFIG --> API

    IAM --> LAMBDA
    LAMBDA --> API

    IAM --> OUT
    LAMBDA --> OUT
    API --> OUT
```

---

## 10. Infrastructure Dependency Flow

```mermaid
flowchart LR
    IAM[Lambda IAM Role]
    LAMBDA[Lambda Function]
    API[API Gateway]
    PERMISSION[Lambda Invoke Permission]
    DEPLOY[API Deployment]
    OUTPUTS[Terraform Outputs]

    IAM --> LAMBDA
    LAMBDA --> PERMISSION
    LAMBDA --> API
    API --> PERMISSION
    API --> DEPLOY

    LAMBDA --> OUTPUTS
    API --> OUTPUTS
```

---

## 11. API Architecture

```mermaid
flowchart TD
    ROOT[API Gateway Root]
    FRIENDLY[/friendly]
    POST[POST Method]
    INTEGRATION[Lambda Integration]
    FUNCTION[Image Analyzer Lambda]
    RESPONSE[API Response]

    ROOT --> FRIENDLY
    FRIENDLY --> POST
    POST --> INTEGRATION
    INTEGRATION --> FUNCTION
    FUNCTION --> RESPONSE
    RESPONSE --> POST
```

The initial API uses a regional API Gateway endpoint.

---

## 12. Deployment Flow

```mermaid
flowchart LR
    DEV[Developer]
    CODE[Python + Terraform]
    VALIDATE[Terraform Validate]
    PLAN[Terraform Plan]
    APPLY[Terraform Apply]
    AWS[AWS Infrastructure]
    TEST[API Testing]

    DEV --> CODE
    CODE --> VALIDATE
    VALIDATE --> PLAN
    PLAN --> APPLY
    APPLY --> AWS
    AWS --> TEST
```

---

## 13. Testing Architecture

```mermaid
flowchart LR
    PYTHON[Python Client]
    IMAGE[PNG / JPEG]
    ENCODE[Base64 Encoding]
    API[API Gateway]
    LAMBDA[Lambda]
    REK[Rekognition]
    RESULT[Test Result]

    IMAGE --> ENCODE
    ENCODE --> PYTHON
    PYTHON -->|POST /friendly| API
    API --> LAMBDA
    LAMBDA --> REK
    REK --> LAMBDA
    LAMBDA --> API
    API --> RESULT
```

Testing will cover at least:

- Good profile photo.
- Photo without a face.
- Photo with multiple faces.
- Photo with closed eyes.
- Photo without a smile.
- Invalid request payload.
- Unsupported image format.

---

## 14. Architecture Evaluation

| Requirement | Architectural Decision | Result |
|---|---|---|
| ML classification | Amazon Rekognition | Satisfied |
| Application integration | API Gateway | Satisfied |
| Business logic | Lambda | Satisfied |
| PNG/JPEG support | Lambda + Rekognition | Satisfied |
| High availability | Managed AWS services | Satisfied |
| Low cost | Serverless pay-per-request | Satisfied |
| Scalability | API Gateway + Lambda + Rekognition | Satisfied |
| No image persistence | No storage layer | Satisfied |
| Python integration | HTTP API + Python client | Satisfied |
| Infrastructure as Code | Terraform | Satisfied |
| Least privilege | Dedicated Lambda IAM permissions | Satisfied |

---

## 15. Architecture Trade-offs

### Amazon Rekognition vs Custom ML Model

Amazon Rekognition was selected because:

- It provides a managed computer-vision capability.
- No training dataset is required.
- No model infrastructure needs to be managed.
- It supports facial attribute analysis.
- It scales with the application.

A custom ML model would provide greater customization but would introduce additional data, training, infrastructure, and operational requirements.

---

### API Gateway + Lambda vs Direct Rekognition Access

The client does not communicate directly with Rekognition because doing so would require distributing AWS credentials and would expose AWS service details to consuming applications.

API Gateway and Lambda provide an abstraction layer that:

- Hides AWS service credentials.
- Encapsulates business logic.
- Allows response customization.
- Provides a standard HTTPS interface.
- Creates a natural location for authentication and authorization enhancements.

---

## 16. Current Architecture vs Future Architecture

```mermaid
flowchart LR
    CURRENT[Current Version]

    CLIENT1[Applications]
    API1[API Gateway]
    LAMBDA1[Lambda]
    REK1[Rekognition]

    CLIENT1 --> API1 --> LAMBDA1 --> REK1
    REK1 --> LAMBDA1 --> API1 --> CLIENT1

    FUTURE[Future Enhancements]

    AUTH[Cognito / IAM]
    WAF[WAF]
    MOD[Content Moderation]
    ASYNC[Async Processing]
    CUSTOM[Custom ML / SageMaker]
    DOMAIN[Custom Domain + ACM]

    API1 -.-> AUTH
    API1 -.-> WAF
    LAMBDA1 -.-> MOD
    LAMBDA1 -.-> ASYNC
    LAMBDA1 -.-> CUSTOM
    API1 -.-> DOMAIN
```

---

## 17. Future Work

The following enhancements are intentionally outside the initial implementation:

### Authentication and Authorization

Add Cognito, IAM authorization, or a private API depending on the consuming application's environment.

### AWS WAF

Protect the public API from unwanted or abusive traffic.

### Custom Domain

Expose the API through a human-friendly custom domain using API Gateway custom domains and ACM.

### Image Moderation

Use Amazon Rekognition `DetectModerationLabels` to detect inappropriate content before accepting a photo as a professional profile image.

### Asynchronous Processing

Move from synchronous analysis to an asynchronous workflow if the number of image-analysis steps grows.

### Custom ML

Use Amazon SageMaker when the required classification cannot be provided adequately by managed Rekognition capabilities.

### Emotion-Based Rules

Extend the current business rules to consider detected emotions if business requirements justify it.