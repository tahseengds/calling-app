'use strict';
const { createLogger, format, transports } = require('winston');

const logger = createLogger({
  level: process.env.DEBUG === 'true' ? 'debug' : 'info',
  format: format.combine(
    format.timestamp(),
    format.json()
  ),
  transports: [new transports.Console()],
});

module.exports = logger;
