#ifndef FREE_MEMORY_POINTERS_H_
#define FREE_MEMORY_POINTERS_H_

/*
 * TODO: the only reason it was ok to do this all in a header file is because it is only included once and in a cpp file so
 * should fix this at some point but we are in a hurry :)
 */

#include <set>
namespace FreeMemory{


class FreeMemoryPointers
{
private:
	FreeMemoryPointers() {}
	std::set<const void *> rawPointers;
	std::set<const void *> ipcPointers;
public:
	static FreeMemoryPointers& getInstance()
	{
		static FreeMemoryPointers instance;
		return instance;
	}

	void
	freeAll() {
		std::cout << "\033[32mFreeMemory:\n"
		                   << "\tRaw: " << rawPointers.size()
		                   << "\n\tIPC: " << ipcPointers.size()
		                   << "\033[0m" << std::endl;

		std::cout << std::endl;

		std::cout << "\033[31mRaw" << std::endl;
		for (auto pointer : rawPointers) {
			std::cout << reinterpret_cast<const long long>(pointer) << std::endl;
		}

		std::cout << std::endl;

		std::cout << "\033[31mIPC" << std::endl;
		for (auto pointer : ipcPointers) {
			std::cout << reinterpret_cast<const long long>(pointer) << std::endl;
		}

		std::set<const void *> pointersToFree;
		std::set_difference(rawPointers.begin(),
				rawPointers.end(),
				ipcPointers.begin(),
				ipcPointers.end(),
				std::inserter(pointersToFree, pointersToFree.end()));

		std::cout << std::endl;

		std::cout << "\033[31mResult" << std::endl;
		for (auto pointer : pointersToFree) {
			std::cout << reinterpret_cast<const long long>(pointer) << std::endl;
		}

		for (auto pointer : pointersToFree) {
			cudaError error = cudaFree(const_cast<void *>(pointer));
			std::cout << "error = " << (error == cudaSuccess) << std::endl;
		}
		std::cout << "\033[0m" << std::endl;

		rawPointers.clear();
		ipcPointers.clear();
	}

	void
	registerRawPointer(const void *pointer) {
		rawPointers.emplace(pointer);
	}

	void
	updateRawPointer(const void *actual, const void *other) {
		//std::replace(rawPointers.begin(), rawPointers.end(), actual, other);
	}

	void
	removeRawPointer(const void *pointer) {
		//std::remove(rawPointers.begin(), rawPointers.end(), pointer);
	}

	void
	registerIPCPointer(const void *pointer) {
		ipcPointers.emplace(pointer);
	}

	FreeMemoryPointers(FreeMemoryPointers const&)               = delete;
	void operator=(FreeMemoryPointers const&)  = delete;

};

}
#endif
