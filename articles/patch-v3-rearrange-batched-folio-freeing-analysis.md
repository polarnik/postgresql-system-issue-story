# [PATCH v3 00/18] Rearrange batched folio freeing -- Анализ серии патчей ядра Linux

**Источник:** https://lore.kernel.org/all/20240227174254.710559-12-willy@infradead.org/T/

**Дата публикации:** 2024-02-27

**Автор серии:** Matthew Wilcox (Oracle) <willy@infradead.org>

---

## 1. Cover Letter (PATCH v3 00/18)

### Описание серии патчей

Помимо очевидных изменений "убрать вызовы compound_head", фундаментальная идея этой серии патчей заключается в том, что итерация по связному списку (linked list) значительно медленнее, чем итерация по массиву (в 5-15 раз медленнее по результатам тестирования автора). Кроме того, поскольку батч folio итерируется три раза, производительность лучше при малом размере массива (15 элементов), чем при батче из сотен элементов -- большой батч дает возможность первым страницам выпасть из кэша процессора к моменту завершения обработки.

Возможно, стоит увеличить размер folio_batch. Автор надеялся, что боты покажут, не появились ли какие-либо регрессии производительности.

### Полный текст cover letter (оригинал)

```
Other than the obvious "remove calls to compound_head" changes, the
fundamental belief here is that iterating a linked list is much slower
than iterating an array (5-15x slower in my testing).  There's also
an associated belief that since we iterate the batch of folios three
times, we do better when the array is small (ie 15 entries) than we do
with a batch that is hundreds of entries long, which only gives us the
opportunity for the first pages to fall out of cache by the time we get
to the end.

It is possible we should increase the size of folio_batch.  Hopefully the
bots let us know if this introduces any performance regressions.
```

### История версий

**v3:**
- Перебазировано на next-20240227
- Добавлена функция `folios_put_refs()` для поддержки unmap больших PTE-mapped folio
- Использован `folio_batch_reinit()` вместо присвоения 0 в `fbatch->nr` для корректного сброса итератора

**v2:**
- Переработан патч `shrink_folio_list()`: mapped folios освобождаются в конце вместо более частого вызова `try_to_unmap_flush()`
- Улучшены описания коммитов
- Использован `pcp_allowed_order()` вместо `PAGE_ALLOC_COSTLY_ORDER` (по замечанию Ryan Roberts)
- Исправлен комментарий `move_folios_to_lru()` (Ryan Roberts)
- Добавлены патчи 15-18
- Собраны теги Reviewed-by от Ryan Roberts

### Статистика

```
 12 files changed, 240 insertions(+), 225 deletions(-)
```

**Затронутые файлы:**
- `include/linux/memcontrol.h`
- `include/linux/mm.h`
- `include/linux/swap.h`
- `mm/internal.h`
- `mm/khugepaged.c`
- `mm/memcontrol.c`
- `mm/memory.c`
- `mm/mlock.c`
- `mm/page_alloc.c`
- `mm/swap.c`
- `mm/swap_state.c`
- `mm/vmscan.c`

---

## 2. Список всех 18 патчей

| # | Название | Автор | Измененные файлы |
|---|---------|-------|------------------|
| 01 | mm: Make folios_put() the basis of release_pages() | Matthew Wilcox (Oracle) | include/linux/mm.h, mm/mlock.c, mm/swap.c |
| 02 | mm: Convert free_unref_page_list() to use folios | Matthew Wilcox (Oracle) | mm/page_alloc.c |
| 03 | mm: Add free_unref_folios() | Matthew Wilcox (Oracle) | mm/internal.h, mm/page_alloc.c |
| 04 | mm: Use folios_put() in __folio_batch_release() | Matthew Wilcox (Oracle) | mm/swap.c |
| 05 | memcg: Add mem_cgroup_uncharge_folios() | Matthew Wilcox (Oracle) | include/linux/memcontrol.h, mm/memcontrol.c |
| 06 | mm: Remove use of folio list from folios_put() | Matthew Wilcox (Oracle) | mm/swap.c |
| 07 | mm: Use free_unref_folios() in put_pages_list() | Matthew Wilcox (Oracle) | mm/swap.c |
| 08 | mm: use __page_cache_release() in folios_put() | Matthew Wilcox (Oracle) | include/linux/memcontrol.h, mm/swap.c |
| 09 | mm: Handle large folios in free_unref_folios() | Matthew Wilcox (Oracle) | mm/page_alloc.c |
| **10** | **mm: Allow non-hugetlb large folios to be batch processed** | Matthew Wilcox (Oracle) | mm/swap.c |
| **11** | **mm: Free folios in a batch in shrink_folio_list()** | Matthew Wilcox (Oracle) | mm/vmscan.c |
| 12 | mm: Free folios directly in move_folios_to_lru() | Matthew Wilcox (Oracle) | mm/vmscan.c |
| 13 | memcg: Remove mem_cgroup_uncharge_list() | Matthew Wilcox (Oracle) | include/linux/memcontrol.h, mm/memcontrol.c |
| 14 | mm: Remove free_unref_page_list() | Matthew Wilcox (Oracle) | mm/internal.h, mm/page_alloc.c |
| 15 | mm: Remove lru_to_page() | Matthew Wilcox (Oracle) | include/linux/mm.h |
| 16 | mm: Convert free_pages_and_swap_cache() to use folios_put() | Matthew Wilcox (Oracle) | mm/swap_state.c |
| 17 | mm: Use a folio in __collapse_huge_page_copy_succeeded() | Matthew Wilcox (Oracle) | mm/khugepaged.c |
| 18 | mm: Convert free_swap_cache() to take a folio | Matthew Wilcox (Oracle) | include/linux/swap.h, mm/khugepaged.c, mm/memory.c, mm/swap_state.c |

---

## 3. Патч #11 -- Критический патч: "mm: Free folios in a batch in shrink_folio_list()"

### Полное сообщение коммита

```
mm: Free folios in a batch in shrink_folio_list()

Use free_unref_page_batch() to free the folios.  This may increase the
number of IPIs from calling try_to_unmap_flush() more often, but that's
going to be very workload-dependent.  It may even reduce the number of
IPIs as we now batch-free large folios instead of freeing them one at
a time.

Signed-off-by: Matthew Wilcox (Oracle) <willy@infradead.org>
Cc: Mel Gorman <mgorman@suse.de>
---
 mm/vmscan.c | 20 +++++++++-----------
 1 file changed, 9 insertions(+), 11 deletions(-)
```

### Полный diff

```diff
diff --git a/mm/vmscan.c b/mm/vmscan.c
index d3c6e84475b9..0c88cb23cc40 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -1026,14 +1026,15 @@ static unsigned int shrink_folio_list(struct list_head *folio_list,
 		struct pglist_data *pgdat, struct scan_control *sc,
 		struct reclaim_stat *stat, bool ignore_references)
 {
+	struct folio_batch free_folios;
 	LIST_HEAD(ret_folios);
-	LIST_HEAD(free_folios);
 	LIST_HEAD(demote_folios);
 	unsigned int nr_reclaimed = 0;
 	unsigned int pgactivate = 0;
 	bool do_demote_pass;
 	struct swap_iocb *plug = NULL;
 
+	folio_batch_init(&free_folios);
 	memset(stat, 0, sizeof(*stat));
 	cond_resched();
 	do_demote_pass = can_demote(pgdat->node_id, sc);
@@ -1432,14 +1433,11 @@ static unsigned int shrink_folio_list(struct list_head *folio_list,
 		 */
 		nr_reclaimed += nr_pages;
 
-		/*
-		 * Is there need to periodically free_folio_list? It would
-		 * appear not as the counts should be low
-		 */
-		if (unlikely(folio_test_large(folio)))
-			destroy_large_folio(folio);
-		else
-			list_add(&folio->lru, &free_folios);
+		if (folio_batch_add(&free_folios, folio) == 0) {
+			mem_cgroup_uncharge_folios(&free_folios);
+			try_to_unmap_flush();
+			free_unref_folios(&free_folios);
+		}
 		continue;
 
 activate_locked_split:
@@ -1503,9 +1501,9 @@ static unsigned int shrink_folio_list(struct list_head *folio_list,
 
 	pgactivate = stat->nr_activate[0] + stat->nr_activate[1];
 
-	mem_cgroup_uncharge_list(&free_folios);
+	mem_cgroup_uncharge_folios(&free_folios);
 	try_to_unmap_flush();
-	free_unref_page_list(&free_folios);
+	free_unref_folios(&free_folios);
 
 	list_splice(&ret_folios, folio_list);
 	count_vm_events(PGACTIVATE, pgactivate);
```

### Подробное объяснение изменений

Этот патч является ключевым звеном в цепочке рефакторинга подсистемы управления памятью ядра Linux. Вот что он делает:

**До патча:**
- `shrink_folio_list()` -- основная функция рекламирования (reclaim) страниц из LRU-списков -- использовала связный список (`LIST_HEAD(free_folios)`) для накопления folio, которые нужно освободить
- Большие folio (`folio_test_large()`) освобождались поштучно через `destroy_large_folio()`
- Маленькие folio добавлялись в связный список через `list_add(&folio->lru, &free_folios)`
- В конце функции весь список освобождался разом через `free_unref_page_list()`

**После патча:**
- Вместо связного списка используется `struct folio_batch free_folios` (массив фиксированного размера, 15 элементов -- `PAGEVEC_SIZE`)
- Все folio (включая большие!) добавляются в батч через `folio_batch_add()`
- Когда батч заполняется (`folio_batch_add()` возвращает 0), происходит немедленное освобождение:
  1. `mem_cgroup_uncharge_folios()` -- снятие зарядов memcg
  2. `try_to_unmap_flush()` -- сброс TLB (может генерировать IPI)
  3. `free_unref_folios()` -- фактическое освобождение страниц
- В конце функции аналогично освобождаются оставшиеся folio в батче

**Почему это важно:**
1. Итерация по массиву из 15 элементов значительно быстрее итерации по связному списку (5-15x по тестам автора) благодаря предсказуемости доступа к памяти и эффективности кэша CPU
2. Большие folio теперь тоже освобождаются через batch-путь, а не поштучно
3. `try_to_unmap_flush()` вызывается чаще (при каждом заполнении батча), что может увеличить число IPI, но автор считает это зависимым от нагрузки

**Критический аспект:** Этот патч, вместе с патчем #10, расширил временное окно между декрементом refcount folio и удалением его из deferred split list, что привело к обнаружению гонки данных (race condition) -- подробнее в разделе 4.

---

## 4. Обзорные комментарии и обсуждение бага

### Обнаружение бага: Ryan Roberts (ARM), 6 марта 2024

Ryan Roberts сообщил о серьезном баге, обнаруженном при тестировании swap с большими folio (mTHP, multi-size THP). Баг проявлялся при нагрузке:

- VM на Ampere Altra: 70 vCPU, 80 ГБ RAM
- RAM-диск 35 ГБ настроен как swap-бэкенд
- memcg ограничение 40 ГБ (для создания давления на память)
- 70 процессов, каждый аллоцирует и записывает 1 ГБ RAM

**Симптомы:**
- `BUG: Bad page state in process usemem pfn:2554a0`
- `kernel BUG at include/linux/mm.h:1120!` (VM_BUG_ON_PAGE: page_ref_count == 0)
- Два CPU одновременно упали в oops на одной и той же странице
- Стек вызовов: `migrate_folio_done` (kcompactd) и `deferred_split_scan` (page fault -> memcg shrinking)

Bisect указал на патч #10 ("mm: Allow non-hugetlb large folios to be batch processed"). При его откате проблема становилась значительно менее воспроизводимой.

### Анализ Matthew Wilcox: Обнаружение гонки данных

Matthew Wilcox провел многочасовой анализ кода и обнаружил **race condition между освобождением folio и `deferred_split_scan()`**:

```
CPU 1: deferred_split_scan:
spin_lock_irqsave(split_queue_lock)
list_for_each_entry_safe()
folio_try_get()
list_move(&folio->_deferred_list, &list);   // Folio перемещен в локальный список
spin_unlock_irqrestore(split_queue_lock)
list_for_each_entry_safe() {
    folio_trylock() <- fails
    folio_put(folio);                        // Refcount уменьшен, но не до 0

CPU 2: folio_put:                            // Другой CPU делает финальный put
folio_undo_large_rmappable
    ds_queue = get_deferred_split_queue(folio);
    spin_lock_irqsave(&ds_queue->split_queue_lock, flags);
        list_del_init(&folio->_deferred_list);
*** В ЭТОТ МОМЕНТ CPU 1 НЕ ДЕРЖИТ split_queue_lock;
*** folio находится в локальном списке CPU 1, который только что был поврежден ***
```

**Суть проблемы:**
1. CPU 1 (deferred_split_scan) перемещает folio из глобальной очереди в локальный список под блокировкой
2. CPU 1 освобождает блокировку и начинает итерировать локальный список
3. CPU 1 делает `folio_put()` -- это НЕ последний refcount
4. CPU 2 делает финальный `folio_put()`, который вызывает `folio_undo_large_rmappable()`
5. `folio_undo_large_rmappable()` берет `split_queue_lock` и удаляет folio из списка через `list_del_init()`
6. Но folio сейчас в **локальном** списке CPU 1, а не в глобальной очереди!
7. `list_del_init()` повреждает локальный список CPU 1 -- дальше может произойти что угодно

Патч #10 расширил временное окно для этой гонки, изменив порядок операций: ранее `folio_undo_large_rmappable()` вызывалось сразу при `folio_put()`, а после патча -- декремент refcount и удаление из deferred list были разнесены во времени.

### Предложенное исправление Matthew Wilcox

Matthew предложил использовать `folio_batch` вместо связного списка через `_deferred_list` в `deferred_split_scan()`:

```diff
-	LIST_HEAD(list);
+	struct folio_batch batch;
```

Ключевая идея: folio остаются в deferred_list (не перемещаются в локальный список), а ссылки (refcount) удерживаются до самого конца, после чего folio_put() вызывается через `folios_put(&batch)`. Таким образом, `folio_undo_large_rmappable()` не может повредить итерируемый список, потому что итерация идет по массиву (folio_batch), а не по linked list.

### Дополнительная находка Yin Fengwei (Intel)

Yin Fengwei заметил различие в проверке `order` между `free_unref_folios()` и `destroy_large_folio()`:

```c
// free_unref_folios():
if (order > 0 && folio_test_large_rmappable(folio))
    folio_undo_large_rmappable(folio);

// destroy_large_folio():
if (folio_test_large_rmappable(folio))
    folio_undo_large_rmappable(folio);
```

Matthew объяснил, что order намеренно очищается в `free_unref_page_prepare() -> free_pages_prepare()` (`page[1].flags &= ~PAGE_FLAGS_SECOND`), поэтому сохраняется в `folio->private`.

---

## 5. Ключевые участники обсуждения

| Участник | Организация | Роль в обсуждении |
|----------|-------------|-------------------|
| **Matthew Wilcox** | Oracle / Infradead.org | Автор всей серии патчей. Обнаружил race condition в deferred_split_scan(). Предложил несколько вариантов исправления. |
| **Ryan Roberts** | ARM | Обнаружил баг при тестировании swap с mTHP на Ampere Altra. Провел bisect. Тестировал все предложенные исправления. Предоставил детальные отчеты об ошибках. |
| **Zi Yan** | NVIDIA | Обсуждал обработку deferred list при миграции страниц. Указал на не связанный с гонкой баг в миграции THP/mTHP и планировал отправить отдельный патч. |
| **Yin Fengwei** | Intel | Заметил различие в проверке folio order между путями освобождения. Задал важные вопросы о состоянии folio. |
| **Andrew Morton** | Основной мейнтейнер mm | Получатель (To:) всех патчей серии. Участвовал в обсуждении финального исправления. |
| **Mel Gorman** | SUSE | В Cc: патча #11 как эксперт по vmscan. |
| **David Hildenbrand** | Red Hat | Дал Reviewed-by для патча #18. |

### Хронология обсуждения бага

| Дата | Событие |
|------|---------|
| 2024-02-27 | Matthew Wilcox публикует серию v3 из 18 патчей |
| 2024-03-06 13:42 | Ryan Roberts сообщает о баге: "Bad page state", oops при swap-тестах |
| 2024-03-06 16:09 | Matthew Wilcox анализирует oops, выдвигает гипотезу о двух CPU, одновременно вызывающих put_folio() |
| 2024-03-06 16:19 | Ryan Roberts подтверждает: проблема воспроизводится и после реверта, но реже |
| 2024-03-06 17:41 | Ryan Roberts: проблема связана с GCC 12.2 и mTHP swap-out кодом |
| 2024-03-06 18:41 | Zi Yan: deferred list в миграции обрабатывается некорректно, но это отдельный баг |
| 2024-03-06 19:55 | **Matthew Wilcox обнаруживает race condition** между folio freeing и deferred_split_scan() |
| 2024-03-06 21:55 | Matthew Wilcox предлагает первый вариант исправления (folio_batch в deferred_split_scan) |
| 2024-03-07 08:56 | Ryan Roberts: "Wow, this would have taken me weeks..." Тестирует исправление |
| 2024-03-07 13:50 | Yin Fengwei замечает аномалию: folio с order:0, но folio_test_large |
| 2024-03-07 14:05 | Matthew Wilcox объясняет намеренную очистку order в free_pages_prepare() |
| 2024-03-07 15:24 | Ryan Roberts: подозревает утечку памяти при освобождении 2M folio |
| 2024-03-07 17:33 | Matthew Wilcox публикует второй вариант исправления (исправлена утечка refcount при неудачном folio_trylock()) |
| 2024-03-07 18:35 | Ryan Roberts замечает fix "mm: fix list corruption in put_pages_list" в mm-unstable |
| 2024-03-08 11:44 | Ryan Roberts: нет oops, но система работает часами вместо минут. Все CPU конфликтуют на deferred split lock |
| 2024-03-08 12:09 | Ryan Roberts диагностирует: проблема в удаленном коде удаления folio из очереди при неудачном folio_try_get() |
| 2024-03-09-03-10 | Продолжение отладки: итерации исправлений, тестирование производительности |

---

## Значимость для расследования

Эта серия патчей демонстрирует классическую ситуацию в разработке ядра:

1. **Оптимизация раскрыла латентный баг** -- гонка данных (race condition) между `deferred_split_scan()` и `folio_put()` существовала и раньше, но окно было настолько узким, что практически не воспроизводилось. Рефакторинг порядка операций расширил это окно.

2. **Подсистема mm/vmscan.c** -- центральная для производительности подсистемы виртуальной памяти. Функция `shrink_folio_list()` -- это "горячий путь" рекламирования страниц, вызываемый при давлении на память (memory pressure). Любые баги здесь критически влияют на стабильность системы под нагрузкой.

3. **Связь с PostgreSQL** -- при интенсивной нагрузке PostgreSQL, когда система испытывает давление на память (shared buffers, work_mem, maintenance_work_mem), ядро активно вызывает именно `shrink_folio_list()` для освобождения страниц. Race condition в этом коде может приводить к:
   - "Bad page state" и kernel oops
   - Утечкам памяти (folio не возвращаются в buddy allocator)
   - Зависаниям системы (contention на deferred split lock)
   - RCU stalls при полном исчерпании памяти
