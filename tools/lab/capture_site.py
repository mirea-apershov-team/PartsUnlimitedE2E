import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright,Error

destination=Path(os.environ['GITHUB_WORKSPACE'])/'artifacts/deployment-evidence'
source=Path(r'C:\sites\PartsUnlimited\Views\Home\Index.cshtml').read_text(encoding='utf-8-sig')
expected='CI/CD delivery verified' if 'CI/CD delivery verified' in source else 'Improved fuel efficiency for everyday driving'
with sync_playwright() as p:
    browser=None
    for channel in ['msedge','chrome']:
        try:
            browser=p.chromium.launch(channel=channel,headless=True)
            break
        except Error:
            continue
    if browser is None:
        raise RuntimeError('No installed Windows browser was available')
    page=browser.new_page(viewport={'width':1600,'height':1100})
    response=page.goto('http://127.0.0.1:8080/',wait_until='domcontentloaded',timeout=120000)
    assert response and response.status==200
    page.wait_for_timeout(1800)
    page.locator('#jumbotron-carousel [data-slide-to="1"]').click()
    page.wait_for_timeout(1000)
    text=page.locator('body').inner_text()
    assert expected in text, (expected,text[:1200])
    page.screenshot(path=str(destination/'website.png'),full_page=True)
    (destination/'browser.json').write_text(json.dumps({'url':page.url,'http_status':response.status,
        'expected_visible_text':expected,'commit':os.environ['GITHUB_SHA'],'real_browser':True},indent=2))
    print('Browser verified visible deployed text:',expected)
    browser.close()
