#include "memory.h"

#include <cstdlib>
#include <new>

namespace gea::framework::memory {

void *Allocator::allocatePreferSpiram(std::size_t size, std::size_t alignment)
{
	if (size == 0) return nullptr;
	if (alignment <= alignof(std::max_align_t)) return std::malloc(size);
	void *ptr = nullptr;
	if (posix_memalign(&ptr, alignment, size) != 0) return nullptr;
	return ptr;
}

void *Allocator::reallocatePreferSpiram(void *ptr, std::size_t size)
{
	if (size == 0) {
		std::free(ptr);
		return nullptr;
	}
	return std::realloc(ptr, size);
}

void Allocator::free(void *ptr) noexcept
{
	std::free(ptr);
}

}  // namespace gea::framework::memory
