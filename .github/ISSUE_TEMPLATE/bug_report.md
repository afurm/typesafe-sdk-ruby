---
name: Bug report
about: Report a problem with the Ruby SDK
labels: bug
---

**Summary**
A clear and concise description of the problem.

**Environment**

- Gem version:
- Ruby version (`ruby -v`):
- Default or custom HTTP adapter:
- Request ID (if available):

**Reproduction**
Minimal code that reproduces the issue. Do **not** include your API key.

```ruby
# your code here
```

**Expected behavior**

**Actual behavior**

**Additional context**
Sanitized logs, stack traces, etc. Debug mode redacts known credential headers, but
request/response bodies and custom headers may contain secrets or customer data. Review
and remove sensitive content before sharing.
