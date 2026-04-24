# Ссылки из статьи "История поиска бага в ядре Linux длиной в год"

## Обзор ссылок

Статья ссылается на 3 ключевых ресурса в ядре Linux, которые описывают причину и исправление бага.

---

## 1. Коммит, внёсший баг (ядро 5.18)

**URL:** https://github.com/torvalds/linux/commit/56a4d67c264e37014b8392cba9869c7fe904ed1e

### Метаданные
- **Заголовок:** `mm/readahead: Switch to page_cache_ra_order`
- **Автор:** Matthew Wilcox (Oracle) <willy@infradead.org>
- **Дата авторства:** 24 июля 2021
- **Дата коммита:** 21 марта 2022

### Описание
> do_page_cache_ra() was being exposed for the benefit of do_sync_mmap_readahead(). Switch it over to page_cache_ra_order() partly because it's a better interface but mostly for the benefit of the next patch.

### Суть изменения
Функция `do_page_cache_ra()` была заменена на `page_cache_ra_order()` в контексте mmap readahead. Изначально это было подготовительное изменение для следующего патча, но именно оно привело к некорректному поведению при освобождении страниц памяти в связке с XFS и `init_on_free`.

### Изменённые файлы
| Файл | Добавлено | Удалено |
|------|-----------|---------|
| mm/filemap.c | +1 | -1 |
| mm/internal.h | +2 | -2 |
| mm/readahead.c | +2 | -2 |

### Ключевое изменение
В `mm/filemap.c` вызов:
```c
do_page_cache_ra(&ractl, ra->size, ra->async_size);
```
был заменён на:
```c
page_cache_ra_order(&ractl, ra, 0);
```

В `mm/readahead.c` функция `do_page_cache_ra` стала `static` (скрыта из внешнего доступа), а `page_cache_ra_order` стала экспортируемой.

---

## 2. Обсуждение серии патчей для исправления (ядро 6.9)

**URL:** https://lore.kernel.org/all/20240227174254.710559-12-willy@infradead.org/T/

### Метаданные
- **Тема:** `[PATCH v3 00/18] Rearrange batched folio freeing`
- **Автор:** Matthew Wilcox (Oracle)
- **Дата:** 27 февраля 2024
- **Серия:** 18 патчей (v3)

### Описание
Серия из 18 патчей, перестраивающая механизм пакетного освобождения folio (структур управления страницами памяти). Патч #12 из серии — тот самый коммит-исправление (`bc2ff4c`), который устранил баг.

### Контекст
Серия патчей оптимизирует процесс освобождения страниц памяти, заменяя поштучное освобождение на пакетное (batch). Это изменение попутно исправило race condition при работе с folio на XFS с включённым `init_on_free`.

**Локальная копия:** Полный контент обсуждения (73+ сообщений, 18 патчей) сохранён в `articles/[PATCH v3 00_18] Rearrange batched folio freeing.mhtml`. Детальный разбор в Markdown — `articles/patch-v3-rearrange-batched-folio-freeing-analysis.md`.

---

## 3. Коммит-исправление (ядро 6.9)

**URL:** https://github.com/torvalds/linux/commit/bc2ff4cbc3294c01f29449405c42ee26ee0e1f59

### Метаданные
- **Заголовок:** `mm: free folios in a batch in shrink_folio_list()`
- **Автор:** Matthew Wilcox (Oracle) <willy@infradead.org>
- **Коммиттер:** Andrew Morton
- **Дата авторства:** 27 февраля 2024
- **Дата коммита:** 4 марта 2024

### Описание
> Use free_unref_page_batch() to free the folios. This may increase the number of IPIs from calling try_to_unmap_flush() more often, but that's going to be very workload-dependent. It may even reduce the number of IPIs as we now batch-free large folios instead of freeing them one at a time.

### Суть изменения
Переработка функции `shrink_folio_list()` для пакетного освобождения folio вместо поштучного. Именно это изменение устранило race condition, приводивший к обнулению страниц памяти при их повторном использовании.

### Изменённые файлы
| Файл | Добавлено | Удалено |
|------|-----------|---------|
| mm/vmscan.c | +9 | -11 |

### Ключевые изменения в mm/vmscan.c
- `LIST_HEAD(free_folios)` → `struct folio_batch free_batch` + `folio_batch_init()`
- Поштучное освобождение → пакетное добавление с условным flush
- `mem_cgroup_uncharge_list()` → `mem_cgroup_uncharge_folios()`
- `free_unref_page_list()` → `free_unref_folios()`

### Соавторы
- Mel Gorman
- David Hildenbrand
- Ryan Roberts

---

## Хронология бага

| Дата | Событие | Ядро |
|------|---------|------|
| Июль 2021 | Написан проблемный код (Matthew Wilcox, Oracle) | — |
| Март 2022 | Коммит `56a4d67` попадает в mainline | 5.18 |
| 2022-2024 | Баг живёт в ядрах 5.18 — 6.8, вызывая случайные сегфолты | 5.18-6.8 |
| Февраль 2024 | Серия патчей v3 "Rearrange batched folio freeing" | — |
| Март 2024 | Коммит-исправление `bc2ff4c` попадает в mainline | 6.9 |

### Важное наблюдение из комментариев
Оба коммита (и сломавший, и починивший) сделаны одним и тем же автором — **Matthew Wilcox из Oracle** — с разницей в ~2 года. Red Hat при этом использовал ядра 5.14 (до бага) и 6.12 (после фикса), "перепрыгнув" проблемный диапазон.

---

## Ключевые технические термины

| Термин | Описание |
|--------|----------|
| **mmap** | Механизм отображения файлов в виртуальную память процесса (BSD, 1980-е) |
| **page folio** | Новая структура управления памятью в Linux, наследник `struct page`, для работы с huge pages |
| **init_on_free** | Параметр ядра Linux (с 5.3): обнуление страниц памяти при освобождении (безопасность) |
| **reclaim** | Процесс освобождения страниц памяти ядром при нехватке свободной памяти |
| **shrink_folio_list()** | Функция ядра для освобождения списка folio при memory reclaim |
| **page_cache_ra_order()** | Функция упреждающего чтения (readahead) страниц в page cache |
| **OOM Killer** | Механизм ядра Linux, убивающий процессы при исчерпании памяти |
| **XFS** | Высокопроизводительная журналируемая ФС, разработана Silicon Graphics (1993) |
