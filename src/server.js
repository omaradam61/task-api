const app = require('./app');

const port = Number(process.env.PORT) || 3000;
const server = app.listen(port, () => {
  console.log(`DevOps Task API listening on port ${port}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down');
  server.close(() => process.exit(0));
});
