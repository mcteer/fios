import {test,expect} from '@playwright/test';
test('hostile source titles remain text and unsafe citation destinations remain inert',async({page})=>{
 await page.route('**/api/chats/**',async route=>{
  const response=await route.fetch();
  const body=(await response.text()).replaceAll('Python release notes','<img src=x onerror=alert(1)>').replaceAll('https://www.python.org/doc/','javascript:alert(1)');
  await route.fulfill({response,body});
 });
 let dialogs=0;page.on('dialog',async d=>{dialogs++;await d.dismiss();});
 await page.goto('/');
 await page.getByLabel('Access password',{exact:true}).fill('browser-test-password');
 await page.getByRole('button',{name:'Enter workspace'}).click();
 await page.getByRole('textbox',{name:'Message Fios'}).fill('Python release web evidence');
 await page.getByRole('button',{name:'Send message',exact:true}).click();
 await expect(page.getByText('Public page evidence retrieved',{exact:true})).toBeVisible();
 await page.getByText('Sources (1) · Supplied to model',{exact:true}).click();
 await expect(page.getByText('Invalid source link',{exact:true})).toBeVisible();
 await expect(page.locator('.web-sources img')).toHaveCount(0);
 await expect(page.locator('.prose a').filter({hasText:'[S1]'})).toHaveCount(0);
 expect(dialogs).toBe(0);
});
for(const width of [1440,390])test(`automatic harness search sources, reset, citations and saved provenance (${width}px)`,async({page})=>{
 await page.setViewportSize({width,height:950});
 await page.goto('/');
 await page.getByLabel('Access password',{exact:true}).fill('browser-test-password');
 await page.getByRole('button',{name:'Enter workspace'}).click();
 await page.getByRole('textbox',{name:'Message Fios'}).fill('Python release web evidence');
 await page.getByRole('button',{name:'Send message',exact:true}).click();
 await expect(page.getByRole('button',{name:'Stop response'})).toHaveCount(0);
 await expect(page.locator('.prose')).toContainText('Python fixture version 3.11');
 await expect(page.locator('.prose')).not.toContainText('Preliminary text');
 await expect(page.getByText('Public page evidence retrieved',{exact:true})).toBeVisible();
 const citation=page.locator('.prose a').filter({hasText:'[S1]'});
 await expect(citation).toHaveAttribute('href','https://www.python.org/doc/');
 await expect(page.locator('.prose a').filter({hasText:'[S5]'})).toHaveCount(0);
 const sourcesControl=page.getByText('Sources (1) · Supplied to model',{exact:true});
 await sourcesControl.focus();
 await sourcesControl.press('Enter');
 await expect(page.getByRole('link',{name:'S1 · Python release notes'})).toBeVisible();
 await expect(page.getByRole('link',{name:'S1 · Python release notes'})).toHaveAttribute('rel','noopener noreferrer');
 await page.reload();
 if(width===390){const menu=page.getByRole('button',{name:/Open sidebar|Open navigation|Show sidebar/});if(await menu.count())await menu.click();}
 const chat=page.getByRole('button',{name:'Python release web evidence',exact:true}).first();
 await expect(chat).toBeVisible();
 await chat.click();
 await expect(page.getByText('Public page evidence retrieved',{exact:true})).toBeVisible();
 await expect(page.locator('.prose')).not.toContainText('Preliminary text');
});
