const path = require('path');
const resolve = require('../config/webpack/resolve');

// HUB component development environment. Storybook telemetry is explicitly disabled.
process.env.STORYBOOK_DISABLE_TELEMETRY = '1';
process.env.NODE_ENV = 'development';
const custom = require('../config/webpack/environment');

module.exports = {
  core: {
    disableTelemetry: true,
  },
  stories: [
    '../stories/**/*.stories.mdx',
    '../app/javascript/**/*.stories.@(js|jsx|ts|tsx)',
  ],
  addons: [
    {
      name: '@storybook/addon-docs',
      options: {
        vueDocgenOptions: {
          alias: {
            '@': path.resolve(__dirname, '../'),
          },
        },
      },
    },
    '@storybook/addon-links',
    '@storybook/addon-essentials',
    {
      name: '@storybook/addon-postcss',
      options: {
        postcssLoaderOptions: {
          implementation: require('postcss'),
        },
      },
    },
  ],
  webpackFinal: config => {
    const newConfig = {
      ...config,
      resolve: {
        ...config.resolve,
        modules: custom.resolvedModules.map(i => i.value),
      },
    };

    newConfig.module.rules.push({
      test: /\.scss$/,
      use: ['style-loader', 'css-loader', 'postcss-loader', 'sass-loader'],
      include: path.resolve(__dirname, '../app/javascript'),
    });

    return newConfig;
  },
};
