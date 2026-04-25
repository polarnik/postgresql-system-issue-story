---
name: "Справка: Marp CLI framework для слайдов"
type: reference
status: done
created: 2026-04-25
source: "texts/slides.example/Allure.TestOps.SpeedUp + marp-cli README"
---

# Marp CLI: справка для создания слайдов

## Ключевые факты

- **Формат:** Markdown-файл с YAML frontmatter
- **Разделитель слайдов:** `---` на отдельной строке
- **Speaker notes:** HTML-комментарии `<!-- текст заметки -->`
- **Экспорт:** HTML, PDF (с заметками), PPTX, PNG/JPEG
- **Темы:** встроенные + кастомные CSS
- **CLI:** `npx @marp-team/marp-cli slide-deck.md` или `brew install marp-cli`

## Структура файла

```markdown
---
marp: true
title: Название доклада
description: Описание
theme: имя-темы
paginate: true
---

<!-- _class: lead -->

# Титульный слайд

## Подзаголовок

---

<!-- Это speaker note — видно только в presenter mode -->

# Обычный слайд

Текст на слайде

---
```

## YAML Frontmatter (глобальные директивы)

| Директива | Значение | Пример |
|-----------|---------|--------|
| `marp` | Включить Marp | `marp: true` |
| `title` | Заголовок | `title: Системные баги` |
| `theme` | Тема CSS | `theme: heisenbug` |
| `paginate` | Нумерация | `paginate: true` |
| `_paginate` | Нумерация (per-slide) | `_paginate: false` |
| `template` | Шаблон | `template: bespoke` |

## Per-slide директивы (HTML-комментарии)

```markdown
<!-- _class: main -->        — CSS-класс слайда
<!-- _paginate: false -->     — отключить нумерацию
<!-- _footer: текст -->       — футер слайда
<!-- _backgroundColor: #000 --> — цвет фона
```

Префикс `_` = применить только к текущему слайду.

## Speaker Notes

```markdown
---

# Заголовок слайда

Текст на слайде

<!-- 
Это заметки для спикера.
Они видны в presenter mode, но не на экране.
Можно писать несколько строк.
-->

---
```

Экспорт заметок: `marp --notes slides.md` → текстовый файл
PDF с заметками: `marp --pdf --pdf-notes slides.md`

## Изображения

### Фоновые (на весь слайд)
```markdown
![bg cover](img/photo.jpg)        — заполнить слайд
![bg w:100%](img/screenshot.png)   — по ширине 100%
![bg h:80%](img/diagram.png)       — по высоте 80%
![bg w:90%](img/graph.png)         — по ширине 90%
```

### Inline (в тексте)
```markdown
![h:55](img/logo.svg)              — инлайн, высота 55px
```

## Текстовое форматирование

```markdown
# Заголовок H1
## Подзаголовок H2
### H3

**Жирный текст** или __жирный__
*Курсив* или _курсив_
`инлайн код`
<s>Зачёркнутый</s>
```

В кастомной теме из примера:
- `**жирный**` → жёлтый цвет (акцент)
- `_курсив_` → полупрозрачный (приглушённый)

## Блоки кода

````markdown
```bash
dd if=/dev/zero of=xfs.file bs=1M count=384
mkfs.xfs -f xfs.file
```

```c
for (;;) {
  if (malloc(1024) == NULL) return 1;
}
```

```sql
SELECT * FROM pg_stat_statements;
```
````

## CSS-классы слайдов (из примера)

```markdown
<!-- _class: lead -->       — титульный слайд (крупные заголовки по центру)
<!-- _class: main -->       — основной контент
<!-- _class: main2 -->      — альтернативный layout
<!-- _class: main problem -->  — слайд "проблема" (другой фон)
<!-- _class: main solution --> — слайд "решение"
<!-- _class: main error -->    — слайд "ошибка"
<!-- _class: title -->         — страница раздела
```

## Кастомная тема (CSS)

Файл `themes/heisenbug.css`:

```css
@charset "UTF-8";
/*!
 * @theme heisenbug
 * @auto-scaling true
 */

section {
    width: 1280px;
    height: 720px;
    background-color: #000;
    color: #fff;
    font-family: 'Roboto';
    font-size: 180%;
}

strong { color: #FFD02F; }          /* жирный = жёлтый */
em { opacity: 0.3; font-style: normal; } /* курсив = приглушённый */

section.main h1 {
    position: absolute;
    top: 20%;
    width: 90%;
}
```

## Структура проекта (из примера)

```
docs/
├── slides.md          — основной файл слайдов
├── themes/
│   ├── heisenbug.css  — кастомная тема
│   └── img/           — изображения темы (логотипы, фоны)
└── img/               — изображения контента (скриншоты, схемы)
```

## Полезные команды CLI

```bash
# Превью с авторефрешем
marp --preview --watch docs/slides.md

# Экспорт в PDF с заметками
marp --pdf --pdf-notes docs/slides.md -o presentation.pdf

# Экспорт в PPTX
marp --pptx docs/slides.md -o presentation.pptx

# Экспорт в HTML
marp docs/slides.md -o index.html

# С кастомной темой
marp --theme docs/themes/heisenbug.css docs/slides.md

# Экспорт speaker notes в текст
marp --notes docs/slides.md
```

## Emoji

Работают напрямую в тексте: 🔍 🔗 🧪 ⬇️ 🔄

(Но по правилам нашего проекта — без эмодзи в файлах.)
