#!/usr/bin/env python3
"""Turn saved public test pages into local test cases.

The EXPECTATIONS below are written by hand from the label printed on the page.
They are not taken from what Clerk answers, so a wrong answer stays wrong.
Anything genuinely ambiguous is left out rather than forced.

  "refused" = must come back with no value, whatever the reason.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract import fields                                    # noqa: E402

SRC = os.environ.get("PAGES", os.path.join(os.environ.get("TMPDIR", "/tmp"), "clerk-webtest"))

# Refresh the saved copies if they are not there. Fetch only - no browser is
# opened and nothing is ever submitted to these sites.
def fetch_missing(urls):
    import subprocess
    for name, url in urls.items():
        path = os.path.join(SRC, name, "index.html")
        if os.path.exists(path):
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        subprocess.run(["curl", "-sL", "--max-time", "30", url, "-o", path], check=False)
        print("  fetched", name)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests", "pages")

# page -> { label or name : expected key }
EXPECT = {
  "fill-identity": {
    "First name": "given_name", "Middle name": "middle_name", "Last name": "family_name",
    "Email": "email", "Phone number": "phone",
    "Street address": "address_line1", "Street address line 2": "address_line2",
    "City": "city", "State or province": "state",
    "ZIP or postal code": "postal_code", "Country": "country",
  },
  "fill-card": {
    # Deliberate: the input is cc-name, and nothing beside a payment card is
    # touched. The name is harmless in itself, but refusing is never the wrong
    # way to be wrong here.
    "Name on card": "refused",
    "Card number": "refused", "CVV": "refused", "Type": "refused",
    "Expiry month": "refused", "Expiry year": "refused",
  },
  "roboform": {
    "First Name": "given_name", "Middle Initial": "middle_name",
    "Last Name": "family_name", "Full Name": "full_name",
    "Company": "company", "Position": "job_title",
    "Address Line 1": "address_line1", "Address Line 2": "address_line2",
    "City": "city", "State / Province": "state", "Country": "country", "Zip": "postal_code",
    "Home Phone": "phone", "Work Telephone": "phone", "Cell Phone": "phone",
    "E-mail": "email", "Web Site": "website",
    "Sex": "sex", "Date Of Birth": "dob", "Birth Place": "place_of_birth",
    "Driver License Number": "drivers_license",
    "Credit Card Number": "refused", "Card Verification Code": "refused",
    "Credit Card Type": "refused", "Comments": "refused", "Custom Message": "refused",
  },
  # Every label here is a section title, so the ONLY useful signal is the name
  # attribute. That makes it the test for the attribute fallback.
  "chrome-autofill": {
    "@address": "address_line1", "@city": "city", "@state": "state",
    "@zip": "postal_code", "@country": "country", "@company": "company",
    "@email": "email", "@phone": "phone",
    "@CCNo": "refused", "@cvc": "refused", "@iban": "refused",
    "@s_address": "address_line1", "@s_city": "city", "@s_zip": "postal_code",
  },
  "formy": {
    "First name": "given_name", "Last name": "family_name", "Job title": "job_title",
    "Radio button": "refused", "Years of experience:": "refused",
  },
}

URLS = {
  "fill-identity": "https://fill.dev/identity",
  "fill-card": "https://fill.dev/credit-card",
  "roboform": "https://www.roboform.com/filling-test-all-fields",
  "chrome-autofill": "https://rsolomakhin.github.io/autofill/",
  "formy": "https://formy-project.herokuapp.com/form",
}

fetch_missing(URLS)
os.makedirs(OUT, exist_ok=True)
for page, want in EXPECT.items():
    path = os.path.join(SRC, page, "index.html")
    if not os.path.exists(path):
        print("  missing", path); continue
    fs = fields(open(path, encoding="utf-8", errors="ignore").read())
    expect = {}
    for i, f in enumerate(fs):
        key = want.get(f["label"]) or want.get("@" + f["name"])
        if key:
            expect[str(i)] = key
    blob = {"name": page, "url": URLS[page], "title": page,
            "fields": fs, "expect": expect}
    with open(os.path.join(OUT, page + ".json"), "w", encoding="utf-8") as fh:
        json.dump(blob, fh, ensure_ascii=False, indent=1)
    print("  %-18s %2d fields, %2d of them checked" % (page, len(fs), len(expect)))
