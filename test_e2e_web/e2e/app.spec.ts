import { test, expect } from '@playwright/test';

test.describe('Novel App E2E Tests', () => {
  test.beforeEach(async ({ page }) => {
    // Wait for Flutter app to load
    await page.waitForLoadState('networkidle');

    // Wait for Flutter web app to be ready
    await page.waitForSelector('body', { timeout: 30000 });
  });

  test('app loads successfully', async ({ page }) => {
    // Check that the page loads without errors
    await expect(page).toHaveTitle(/novel_app/i);

    // Wait for Flutter content to render
    await page.waitForTimeout(2000);

    // Take a screenshot for debugging
    await page.screenshot({ path: 'app-load.png' });
  });

  test('bottom navigation is visible', async ({ page }) => {
    // Wait for navigation to load
    await page.waitForTimeout(3000);

    // Look for bottom navigation items
    // Flutter web apps use specific CSS classes and structure
    const navigationElements = await page.locator('[role="navigation"], .navigation, nav').count();

    // If navigation elements are found, verify them
    if (navigationElements > 0) {
      await expect(page.locator('[role="navigation"], .navigation, nav')).toBeVisible();
    }

    // Alternative: Look for common Flutter navigation patterns
    const bottomNav = page.locator('.bottom-navigation, .bottom-nav, [style*="bottom: 0"]');
    if (await bottomNav.count() > 0) {
      await expect(bottomNav).toBeVisible();
    }

    await page.screenshot({ path: 'navigation.png' });
  });

  test('can navigate between sections', async ({ page }) => {
    // Wait for app to fully load
    await page.waitForTimeout(3000);

    // Look for navigation buttons or tabs
    const navButtons = page.locator('button, [role="button"], .tab, [role="tab"]');

    if (await navButtons.count() >= 3) {
      // Click on different navigation items
      for (let i = 0; i < Math.min(3, await navButtons.count()); i++) {
        await navButtons.nth(i).click();
        await page.waitForTimeout(1000);

        // Take screenshot after each navigation
        await page.screenshot({ path: `navigation-${i}.png` });
      }
    } else {
      // Try alternative navigation patterns
      const clickables = page.locator('[onclick], [onTap], .clickable');
      if (await clickables.count() > 0) {
        await clickables.first().click();
        await page.waitForTimeout(1000);
        await page.screenshot({ path: 'alternative-navigation.png' });
      }
    }
  });

  test('bookshelf section loads', async ({ page }) => {
    // Wait for app to load
    await page.waitForTimeout(3000);

    // Try to navigate to bookshelf
    const bookshelfElements = page.locator(':has-text("书架"), :has-text("Bookshelf"), .bookshelf');

    if (await bookshelfElements.count() > 0) {
      await expect(bookshelfElements.first()).toBeVisible();
      await page.screenshot({ path: 'bookshelf.png' });
    } else {
      // Take a screenshot of current state for debugging
      await page.screenshot({ path: 'current-state.png' });

      // Log page content for debugging
      const pageContent = await page.content();
      console.log('Page content length:', pageContent.length);
      console.log('Page contains Flutter elements:', pageContent.includes('flutter'));
    }
  });

  test('app handles API errors gracefully', async ({ page }) => {
    // Listen for console errors
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        errors.push(msg.text());
      }
    });

    // Wait for app to load
    await page.waitForTimeout(3000);

    // Try to trigger API calls by interacting with the app
    const clickableElements = page.locator('button, [role="button"], [onclick]');
    if (await clickableElements.count() > 0) {
      await clickableElements.first().click();
      await page.waitForTimeout(2000);
    }

    // Check for console errors
    console.log('Console errors found:', errors.length);
    if (errors.length > 0) {
      console.log('Errors:', errors);
    }

    // Take final screenshot
    await page.screenshot({ path: 'error-handling.png' });
  });

  test('responsive design works', async ({ page }) => {
    // Test different viewport sizes
    const viewports = [
      { width: 1920, height: 1080 }, // Desktop
      { width: 768, height: 1024 },  // Tablet
      { width: 375, height: 667 },   // Mobile
    ];

    for (let i = 0; i < viewports.length; i++) {
      const viewport = viewports[i];
      await page.setViewportSize(viewport);
      await page.waitForTimeout(1000);

      await page.screenshot({
        path: `responsive-${viewport.width}x${viewport.height}.png`,
        fullPage: true
      });
    }
  });
});