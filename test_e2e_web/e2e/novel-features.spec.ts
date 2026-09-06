import { test, expect } from '@playwright/test';

test.describe('Novel App Features', () => {
  test.beforeEach(async ({ page }) => {
    // Wait for Flutter app to load completely
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Set up console error tracking
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.log('Console error:', msg.text());
      }
    });

    // Set up request monitoring
    page.on('request', request => {
      console.log('Request:', request.method(), request.url());
    });

    page.on('response', response => {
      console.log('Response:', response.status(), response.url());
    });
  });

  test('bookshelf management', async ({ page }) => {
    await page.waitForTimeout(3000);

    // Look for bookshelf or library section
    const bookshelfSelectors = [
      ':has-text("书架")',
      ':has-text("Bookshelf")',
      ':has-text("我的书架")',
      ':has-text("My Library")',
      '.bookshelf',
      '.library',
      '[data-testid="bookshelf"]'
    ];

    let bookshelfFound = false;
    for (const selector of bookshelfSelectors) {
      const element = page.locator(selector);
      if (await element.count() > 0) {
        bookshelfFound = true;
        console.log(`Found bookshelf with selector: ${selector}`);
        await expect(element.first()).toBeVisible();
        break;
      }
    }

    // Try to navigate to bookshelf if not already visible
    if (!bookshelfFound) {
      // Look for navigation tabs
      const navTabs = page.locator('button, [role="button"], [role="tab"]');
      const tabCount = await navTabs.count();

      for (let i = 0; i < Math.min(tabCount, 5); i++) {
        await navTabs.nth(i).click();
        await page.waitForTimeout(1000);

        // Check if bookshelf is now visible
        for (const selector of bookshelfSelectors) {
          const element = page.locator(selector);
          if (await element.count() > 0) {
            bookshelfFound = true;
            console.log(`Found bookshelf after clicking tab ${i}`);
            break;
          }
        }

        if (bookshelfFound) break;
      }
    }

    await page.screenshot({ path: 'bookshelf-state.png' });

    // If bookshelf is found, try interacting with it
    if (bookshelfFound) {
      // Look for novel items or empty state
      const novelItems = page.locator('.novel-item, .book-item, .item');
      const emptyState = page.locator(':has-text("空"), :has-text("empty"), :has-text("暂无")');

      if (await novelItems.count() > 0) {
        console.log(`Found ${await novelItems.count()} novel items`);
        // Try clicking on first novel
        await novelItems.first().click();
        await page.waitForTimeout(2000);
        await page.screenshot({ path: 'novel-details.png' });
      } else if (await emptyState.count() > 0) {
        console.log('Bookshelf is empty - this is expected for first-time users');
        await expect(emptyState.first()).toBeVisible();
      }
    }
  });

  test('settings and configuration', async ({ page }) => {
    await page.waitForTimeout(3000);

    // Look for settings or configuration
    const settingsSelectors = [
      ':has-text("设置")',
      ':has-text("Settings")',
      ':has-text("配置")',
      ':has-text("Config")',
      '.settings',
      '.config',
      '[data-testid="settings"]'
    ];

    // Navigate through different tabs to find settings
    const navElements = page.locator('button, [role="button"], [role="tab"]');
    const navCount = await navElements.count();

    for (let i = 0; i < Math.min(navCount, 5); i++) {
      await navElements.nth(i).click();
      await page.waitForTimeout(1000);

      for (const selector of settingsSelectors) {
        const settingsElement = page.locator(selector);
        if (await settingsElement.count() > 0) {
          console.log(`Found settings with selector: ${selector}`);
          await expect(settingsElement.first()).toBeVisible();

          // Try clicking on settings
          await settingsElement.first().click();
          await page.waitForTimeout(2000);

          await page.screenshot({ path: 'settings-page.png' });
          return; // Settings found and tested
        }
      }
    }

    console.log('Settings not found, taking screenshot of available navigation');
    await page.screenshot({ path: 'no-settings-found.png' });
  });

  test('error handling and loading states', async ({ page }) => {
    await page.waitForTimeout(3000);

    // Monitor for error states
    const errorSelectors = [
      ':has-text("错误")',
      ':has-text("Error")',
      ':has-text("失败")',
      ':has-text("Failed")',
      ':has-text("网络")',
      ':has-text("Network")',
      '.error',
      '.error-message',
      '[data-testid="error"]'
    ];

    // Monitor for loading states
    const loadingSelectors = [
      ':has-text("加载")',
      ':has-text("Loading")',
      ':has-text("请稍候")',
      ':has-text("Please wait")',
      '.loading',
      '.spinner',
      '.progress',
      '[data-testid="loading"]'
    ];

    // Try to trigger various actions that might show loading or error states
    const clickableElements = page.locator('button, [role="button"], [onclick]');
    const clickCount = Math.min(3, await clickableElements.count());

    for (let i = 0; i < clickCount; i++) {
      await clickableElements.nth(i).click();
      await page.waitForTimeout(2000);

      // Check for loading states
      for (const selector of loadingSelectors) {
        const loadingElement = page.locator(selector);
        if (await loadingElement.count() > 0) {
          console.log(`Found loading state: ${selector}`);
          await page.screenshot({ path: `loading-${i}.png` });

          // Wait for loading to complete
          await page.waitForTimeout(3000);
          break;
        }
      }

      // Check for error states
      for (const selector of errorSelectors) {
        const errorElement = page.locator(selector);
        if (await errorElement.count() > 0) {
          console.log(`Found error state: ${selector}`);
          await page.screenshot({ path: `error-${i}.png` });
        }
      }
    }

    await page.screenshot({ path: 'final-state.png' });
  });

  test('accessibility and usability', async ({ page }) => {
    await page.waitForTimeout(3000);

    // Test keyboard navigation
    await page.keyboard.press('Tab');
    await page.waitForTimeout(500);

    // Check if focus is visible
    const focusedElement = await page.locator(':focus');
    if (await focusedElement.count() > 0) {
      console.log('Keyboard navigation working');
      await page.screenshot({ path: 'keyboard-navigation.png' });
    }

    // Test with reduced motion (if supported)
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'reduced-motion.png' });

    // Test high contrast mode
    await page.emulateMedia({ forcedColors: 'active' });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: 'high-contrast.png' });

    // Reset media emulation
    await page.emulateMedia({ reducedMotion: 'no-preference', forcedColors: 'none' });
  });
});