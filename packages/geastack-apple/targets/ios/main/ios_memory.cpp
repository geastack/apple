#include "memory.h"

#include <cstddef>
#include <cstdlib>

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

namespace gea::platform::memory {

std::uint32_t Memory::internalFree() { return 0; }
std::uint32_t Memory::internalLargestFreeBlock() { return 0; }
std::uint32_t Memory::internalMinimumFree() { return 0; }
std::uint32_t Memory::psramFree() { return 0; }
std::uint32_t Memory::currentTaskStackHighWaterMark() { return 0; }
std::uint32_t Memory::geaMainStackBytes() { return 0; }
std::uint32_t Memory::geaInitStackBytes() { return 0; }
std::uint32_t Memory::appFrameStackWords() { return 0; }
std::uint32_t Memory::appFrameStackBytes() { return 0; }
std::uint32_t Memory::displayFlushConfiguredRows() { return 0; }
std::uint32_t Memory::displayFlushConfiguredDepth() { return 0; }
std::uint32_t Memory::displayFlushBufferMaxBytes() { return 0; }
std::uint32_t Memory::displayFlushRows() { return 0; }
std::uint32_t Memory::displayFlushDepth() { return 0; }
std::uint32_t Memory::displayFlushBufferBytes() { return 0; }

// No internal/external split here, so there is nothing to hold back for the
// display; the caller treats nullptr as "no reserve" and carries on.
void *Memory::reserveInternalDma(std::size_t) { return nullptr; }
void Memory::releaseInternalDma(void *) {}
}  // namespace gea::platform::memory
