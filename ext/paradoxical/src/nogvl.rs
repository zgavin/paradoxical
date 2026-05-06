//! GVL-release helper for running CPU-bound Rust code in parallel.
//!
//! Ruby's GVL serializes execution of all Ruby threads — only one can
//! be running Ruby code at a time. C extensions can release the GVL
//! while doing pure-native work (no Ruby calls, no allocations of
//! Ruby objects), letting other Ruby threads run on other cores.
//! When the closure returns, the GVL is reacquired before control
//! returns to Ruby code.
//!
//! magnus 0.8 doesn't expose a friendly wrapper for
//! `rb_thread_call_without_gvl`, so we shim through `rb-sys`
//! ourselves.

use std::ffi::c_void;
use std::ptr;

use rb_sys::rb_thread_call_without_gvl;

/// Runs `f` with the GVL released. The closure must not call into
/// Ruby in any way — no `Value` operations, no allocations of Ruby
/// objects, no `Ruby` handle use. Pure Rust / C only.
///
/// The closure must not panic. (Catching unwinds adds measurable
/// overhead per call. pest's parser doesn't panic on input we can't
/// handle — it returns an `Err` — so the caller's invariants are
/// the actual safety net.)
pub fn nogvl<F, R>(f: F) -> R
where
    F: FnOnce() -> R,
{
    // The closure has to round-trip through a `*mut c_void`. Use an
    // `Option` so we can take the closure out by value inside the
    // callback without needing `F: Copy`.
    let mut state: (Option<F>, Option<R>) = (Some(f), None);

    unsafe extern "C" fn callback<F, R>(arg: *mut c_void) -> *mut c_void
    where
        F: FnOnce() -> R,
    {
        let state = unsafe { &mut *(arg as *mut (Option<F>, Option<R>)) };
        let f = state
            .0
            .take()
            .expect("nogvl callback called without closure");
        state.1 = Some(f());
        ptr::null_mut()
    }

    unsafe {
        rb_thread_call_without_gvl(
            Some(callback::<F, R>),
            &mut state as *mut _ as *mut c_void,
            None, // no unblock function — pest parse is fast & uninterruptible
            ptr::null_mut(),
        );
    }

    state.1.take().expect("nogvl callback didn't run")
}
