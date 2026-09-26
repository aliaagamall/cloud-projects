# Lambda@Edge Language Routing Test Report

## Test Information

- Distribution: CloudFront
- Test object: temporary
- Languages: English and Spanish

## Results

| Test | Result |
|---|---|
| CloudFront deployed | PASS |
| Lambda@Edge origin-request association | PASS |
| CloudFront uses OAI | PASS |
| CloudFront does not use OAC | PASS |
| English S3 public access blocked | PASS |
| Spanish S3 public access blocked | PASS |
| English routing | PASS |
| Spanish routing | PASS |
| Unsupported language fallback | PASS |

## Summary

- Passed: 9
- Failed: 0

