# Personal Website — Requirements

## 1. Overview

The Personal Website project is a static website that presents a professional CV and personal information through a publicly accessible web interface.

The solution should allow the website owner to maintain professional content such as personal information, education, work experience, skills, and projects, while also supporting images and providing basic insights through website monitoring data.

The requirements are divided into functional and non-functional requirements.

---

# 2. Functional Requirements

## FR-01 — CV Content Management

### Requirement

The website must allow the owner to create, edit, and update CV-related content, including:

- Personal information
- Education
- Work experience
- Skills
- Projects

### What does this require?

The website needs a reliable way to store and serve its website content.

### Required capability

Persistent storage for static website files.

### Resulting service

**Amazon S3**

Amazon S3 is suitable for storing the website's HTML, CSS, JavaScript, and other static assets without requiring a web server.

---

## FR-02 — Image Support

### Requirement

The website must support non-text content such as profile images and other images used by the website.

### What does this require?

The architecture needs to store and retrieve binary objects such as image files in addition to text-based website files.

### Required capability

Object storage for static assets.

### Resulting service

**Amazon S3**

S3 stores objects such as images, HTML files, CSS files, and JavaScript files using the same object-storage model.

---

## FR-03 — Internet Accessibility

### Requirement

The website must be accessible to users through the internet using standard web browsers.

### What does this require?

The website needs a publicly reachable content-delivery layer that can serve static content over HTTPS.

### Required capability

Global content delivery and HTTPS access.

### Resulting service

**Amazon CloudFront**

CloudFront provides a globally distributed content-delivery layer in front of the S3 origin.

The S3 bucket itself does not need to be publicly accessible. CloudFront can retrieve objects from the bucket using Origin Access Control (OAC).

---

## FR-04 — Website Insights

### Requirement

The solution must provide the ability to generate insights based on website usage and delivery data.

### What does this require?

The architecture needs monitoring capabilities that provide metrics about requests, errors, traffic, and content delivery.

### Required capability

Monitoring and metrics collection.

### Resulting service

**Amazon CloudWatch**

CloudWatch provides metrics that can be used to monitor the website and evaluate traffic and error behavior.

Relevant metrics include:

- Requests
- 4xx errors
- 5xx errors
- Data transferred / downloaded content
- Other available CloudFront and S3 metrics relevant to the implementation

---

# 3. Non-Functional Requirements

## NFR-01 — Low Latency

### Requirement

The website should provide low-latency access to users.

### What does this require?

Static content should be served from locations that are geographically closer to users whenever possible.

### Required capability

Edge-based content caching and global content delivery.

### Resulting service

**Amazon CloudFront**

CloudFront caches static content at edge locations, reducing the need to retrieve every request directly from the S3 origin.

---

## NFR-02 — High Availability

### Requirement

The website should remain available and should not depend on a single manually managed web server.

### What does this require?

The architecture should use highly available managed services and avoid unnecessary server dependencies.

### Required capability

Highly available storage and distributed content delivery.

### Resulting services

**Amazon S3 + Amazon CloudFront**

S3 provides durable and highly available object storage, while CloudFront provides distributed content delivery.

Together, they remove the need to operate a traditional web server for this static website.

---

## NFR-03 — Maintainability

### Requirement

The website should be easy to maintain and update.

### What does this require?

The solution should minimize infrastructure that must be manually configured and maintained.

### Required capability

Managed services with a simple architecture and independently manageable website assets.

### Resulting services

**Amazon S3 + Amazon CloudFront**

The website content can be updated as objects in S3, while CloudFront handles content distribution.

Infrastructure will be managed through Infrastructure as Code during implementation.

---

## NFR-04 — Low Cost

### Requirement

The solution should have low operating costs and follow a pay-as-you-go model.

### What does this require?

The architecture should avoid continuously running servers when they are not required.

### Required capability

Managed, usage-based cloud services.

### Resulting services

**Amazon S3 + Amazon CloudFront + Amazon CloudWatch**

The static website does not require continuously running compute infrastructure.

This reduces operational overhead and avoids the cost of maintaining dedicated web servers for the application.

Actual cost depends on traffic, storage, requests, data transfer, and monitoring usage.

---

# 4. Requirements Summary

| ID | Requirement | Required Capability | AWS Service |
|---|---|---|---|
| FR-01 | CV Content Management | Object storage | Amazon S3 |
| FR-02 | Image Support | Object storage for static assets | Amazon S3 |
| FR-03 | Internet Accessibility | Global content delivery | Amazon CloudFront |
| FR-04 | Website Insights | Monitoring and metrics | Amazon CloudWatch |
| NFR-01 | Low Latency | Edge caching | Amazon CloudFront |
| NFR-02 | High Availability | Highly available storage and distributed delivery | Amazon S3 + CloudFront |
| NFR-03 | Maintainability | Managed services and simple architecture | S3 + CloudFront |
| NFR-04 | Low Cost | Usage-based managed services | S3 + CloudFront + CloudWatch |

---

# 5. Requirement-to-Service Decision

The service selection follows this decision process:

```text
Requirement
    ↓
What capability is required?
    ↓
What type of infrastructure provides that capability?
    ↓
Which AWS service provides it?
    ↓
Evaluate the service against alternatives and project constraints
```

The architecture is therefore derived from the project requirements rather than selecting AWS services first and fitting the requirements around them.