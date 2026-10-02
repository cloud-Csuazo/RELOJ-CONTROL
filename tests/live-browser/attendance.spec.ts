import {test,expect} from '@playwright/test';
const A='10000000-0000-4000-8000-000000000001';
test('worker marks offline, synchronizes once, completes lunch and sees immutable history',async({page,context})=>{
 await page.goto('/login');await page.getByLabel('Correo electrónico').fill('suacof@example.test');await page.getByLabel('Contraseña',{exact:true}).fill('Local-Fixture-Only-2026!');await page.getByRole('button',{name:'Iniciar sesión',exact:true}).click();await expect(page).toHaveURL(new RegExp(`/empresas/${A}`));
 await page.setViewportSize({width:390,height:844});const journey=page.locator('.journey');await expect(journey.getByRole('button',{name:'Inicio de jornada',exact:true})).toBeEnabled();
 await context.setOffline(true);await journey.getByRole('button',{name:'Inicio de jornada',exact:true}).click();await expect(journey.getByText('1 marcación(es) pendiente(s).',{exact:false})).toBeVisible();
 await context.setOffline(false);await expect(journey.getByText('Marcación registrada con hora del servidor.',{exact:true})).toBeVisible();await expect(journey.getByRole('button',{name:'Inicio de colación',exact:true})).toBeEnabled();
 for(const kind of ['Inicio de colación','Fin de colación','Fin de jornada']){await journey.getByRole('button',{name:kind,exact:true}).click();await expect(journey.getByText('Marcación registrada con hora del servidor.',{exact:true})).toBeVisible();await expect(journey.getByRole('button',{name:kind,exact:true})).toHaveCount(0);}
 await expect(journey.getByText('Jornada finalizada',{exact:true})).toBeVisible();await expect(page.locator('tbody tr')).toHaveCount(4);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBeTruthy();await page.screenshot({path:'screenshots/journey-mobile.png',fullPage:true});
});

