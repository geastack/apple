#pragma once
#include "native_identity.h"
#include "ui/selector.h"
#include "ui/tree_internal.h"
namespace gea::macos {
// Native callbacks keep their original allocation lease. Disabled state is
// resolved from the live Tree at the mutation boundary, not cached NSControl
// appearance; cancellation still uses allocation-only admission.
inline bool controlAdmitted(int node, const gea::framework::identity::Owner &owner) {
 return gea::framework::identity::current(node, owner) &&
        !gea::embedded::ui::selector::disabled(gea::embedded::ui::Tree::instance(), node);
}
}
