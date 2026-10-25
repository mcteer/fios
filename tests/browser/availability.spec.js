import {test, expect} from '@playwright/test';

test('serving hosts and unavailable models are explicit; recovery preserves selected model and draft', async ({page}) => {
  let available=true;
  await page.route('**/api/models',route=>route.fulfill({json:{
    checkedAt:Date.now(),
    hosts:[{name:'gateway',status:'available'},{name:'studio-a',status:available?'available':'unavailable'}],
    models:[{id:'test/coding-model@studio-a',loaded:false,capabilities:['chat'],peer:'studio-a',host:'studio-a',availability:available?'available':'unavailable',reason:available?'ok':'host_down'},
      {id:'test/text-only',loaded:true,capabilities:['chat'],availability:'available',reason:'ok'}]
  }}));
  await page.goto('/');
  await page.getByLabel('Access password',{exact:true}).fill('browser-test-password');
  await page.getByRole('button',{name:'Enter workspace'}).click();
  await page.getByRole('button',{name:'Choose model'}).click();
  const option=page.locator('.model-option').filter({hasText:'coding-model'});
  await option.click();
  await page.getByRole('textbox',{name:'Message Fios'}).fill('Keep this draft');
  await expect(page.getByRole('button',{name:'Send message',exact:true})).toBeEnabled();
  available=false;
  await page.getByRole('button',{name:'Choose model'}).click();
  await expect(page.getByLabel('Serving host status')).toContainText('studio-a: Offline');
  await expect(option).toBeDisabled();
  await expect(option).toContainText('Host offline');
  await expect(page.getByRole('button',{name:'Send message',exact:true})).toBeDisabled();
  await expect(page.getByRole('button',{name:'Choose model'})).toContainText('coding-model');
  available=true;
  await page.getByRole('button',{name:'Refresh models'}).click();
  await expect(page.getByLabel('Serving host status')).toContainText('studio-a: Online');
  await expect(option).toBeEnabled();
  await expect(option).toContainText('On demand');
  await expect(page.getByRole('button',{name:'Send message',exact:true})).toBeEnabled();
  await expect(page.getByRole('textbox',{name:'Message Fios'})).toHaveValue('Keep this draft');
  await expect(page.locator('.message')).toHaveCount(0);
});
