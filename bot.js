const {Telegraf} = require('telegraf');
const {spawn} = require('child_process');
const fs = require('fs');
require('dotenv').config();

// Получаем токен из .env
const bot = new Telegraf(process.env.BOT_TOKEN);

function log(data) {
  console.log(data.toString());
}

// Обработчик команд на ссылки
bot.on('text', async (ctx) => {
  const url = ctx.message.text;
  var out = "";

  function log2(data) {
    console.log(data.toString());
    ctx.reply(data);
  }

  log2('Скачиваю видео...');

  const process = spawn('yt-dlp', ['-o', '/downloads/%(title)s.%(ext)s', url]);

  process.stdout.on('data', (data) => {
    out += data;
    log(data);
  });

  process.stderr.on('data', log);
  process.on('error', log);

  process.on('close', (code) => {
    if (code !== 0) {
      log2(`Процесс завершился с кодом ошибки: ${code}`);
      return;
    }

    log2('Видео успешно скачано.');

    // Ищем скачанный файл
    var downloadedFile =
      out.match(/^\[download] (.+) has already been downloaded$/m)?.[1] ||
      out.match(/^\[Merger] Merging formats into "(.+)"$/m)?.[1] ||
      out.match(/^\[download] Destination: (.+)$/m)?.[1] ||
      null;

    if (downloadedFile && fs.existsSync(downloadedFile)) {
      ctx.replyWithVideo({source: downloadedFile});
    } else {
      log2(`Файл "${downloadedFile}" не найден.`);
    }
  });
});

// Запуск бота
bot.launch();
log('Бот запущен.');
