//! Bounded ownership of renderers, with independent locks for unrelated clips.

use lru::LruCache;
use std::hash::Hash;
use std::num::NonZeroUsize;
use std::sync::{Arc, Mutex};

type Slot<Value> = Arc<Mutex<Option<Value>>>;

pub(crate) struct Cache<Key, Value> {
    entries: Mutex<LruCache<Key, Slot<Value>>>,
}

impl<Key: Hash + Eq, Value> Cache<Key, Value> {
    pub(crate) fn new(capacity: NonZeroUsize) -> Self {
        Self {
            entries: Mutex::new(LruCache::new(capacity)),
        }
    }

    /// Returns a slot without doing initialization, rendering, or GPU destruction under the cache lock.
    pub(crate) fn slot(&self, key: Key) -> Slot<Value> {
        let (slot, evicted) = {
            let mut entries = self.entries.lock().expect("renderer cache mutex poisoned");
            if let Some(slot) = entries.get(&key) {
                return Arc::clone(slot);
            }
            let slot = Arc::new(Mutex::new(None));
            let evicted = entries.push(key, Arc::clone(&slot));
            (slot, evicted)
        };
        drop(evicted);
        slot
    }

    /// Active frames retain their slots until completion; idle GPU resources are released outside the lock.
    pub(crate) fn clear(&self) {
        let retired = {
            let mut entries = self.entries.lock().expect("renderer cache mutex poisoned");
            let capacity = entries.cap();
            std::mem::replace(&mut *entries, LruCache::new(capacity))
        };
        drop(retired);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reuses_slots_and_evicts_the_least_recently_used() {
        let cache = Cache::<u32, u32>::new(NonZeroUsize::new(2).unwrap());
        let first = cache.slot(1);
        let second = cache.slot(2);
        assert!(Arc::ptr_eq(&first, &cache.slot(1)));
        let _third = cache.slot(3);
        assert!(!Arc::ptr_eq(&second, &cache.slot(2)));
    }

    #[test]
    fn clearing_does_not_destroy_an_active_frame() {
        let cache = Cache::new(NonZeroUsize::new(1).unwrap());
        let active = cache.slot("clip");
        *active.lock().unwrap() = Some(42);
        cache.clear();
        assert_eq!(*active.lock().unwrap(), Some(42));
        assert!(cache.slot("clip").lock().unwrap().is_none());
    }

    #[test]
    fn rendering_one_clip_does_not_lock_another() {
        let cache = Cache::<u32, u32>::new(NonZeroUsize::new(2).unwrap());
        let first = cache.slot(1);
        let second = cache.slot(2);
        let _rendering = first.lock().unwrap();
        assert!(second.try_lock().is_ok());
        assert!(Arc::ptr_eq(&first, &cache.slot(1)));
    }
}
