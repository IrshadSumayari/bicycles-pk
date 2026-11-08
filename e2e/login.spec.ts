import { expect, test } from '@playwright/test';

test('login page renders', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /bicycles pos/i })).toBeVisible();
  await expect(page.getByPlaceholder('Enter your email')).toBeVisible();
  await expect(page.getByPlaceholder('Enter your password')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign In' })).toBeEnabled();
});

test('staff sign-up is not offered once the store is set up', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('Ask your store administrator')).toBeVisible();
  await expect(page.getByRole('button', { name: /create the administrator account/i })).toHaveCount(0);
});
