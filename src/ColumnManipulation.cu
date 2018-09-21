
//TODO: in theory  we want to get rid of this
// we should be using permutation iterators when we can

#include "ColumnManipulation.cuh"

#include <thrust/functional.h>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/copy.h>
#include <thrust/remove.h>
#include <thrust/iterator/counting_iterator.h>

#include <thrust/execution_policy.h>
#include <thrust/iterator/iterator_adaptor.h>
#include <thrust/iterator/transform_iterator.h>



template <typename InputType>
struct negative_to_zero : public thrust::unary_function< InputType, InputType>
{
	__host__ __device__
	InputType operator()(InputType x)
	{
		return x < 0 ? 0 : x;
	}
};

const size_t NUM_ELEMENTS_PER_THREAD_GATHER_BITS = 32;
template <typename BitContainer, typename Index>
__global__ void gather_bits(
		const Index*        __restrict__ indices,
		const BitContainer* __restrict__ bit_data,
		BitContainer* __restrict__ gathered_bits,
		gdf_size_type                    num_indices
){



	size_t thread_index = blockIdx.x * blockDim.x + threadIdx.x ;
	size_t element_index = NUM_ELEMENTS_PER_THREAD_GATHER_BITS * thread_index;
	while( element_index < num_indices){

		BitContainer current_bits;

		for(size_t bit_index = 0; bit_index < NUM_ELEMENTS_PER_THREAD_GATHER_BITS; bit_index++){
			//NOTE!!! if we assume that sizeof BitContainer is smaller than the required padding of 64bytes for valid_ptrs
			//then we dont have to do this check
			if((element_index + bit_index) < num_indices){
				Index permute_index = indices[element_index + bit_index];
				bool is_bit_set;
				if(permute_index >=  0){
					//this next line is failing
					is_bit_set = bit_data[permute_index / NUM_ELEMENTS_PER_THREAD_GATHER_BITS] & (1u << (permute_index % NUM_ELEMENTS_PER_THREAD_GATHER_BITS));
					//					is_bit_set = true;
				}else{
					is_bit_set = false;
				}
				current_bits = (current_bits  & ~(1u<<bit_index)) | (static_cast<unsigned int>(is_bit_set) << bit_index); //seems to work
				/*
				 * this is effectively what hte code above is doing but it should help us avoid thread divergence
				if(is_bit_set){
					current_bit|= 1<<bit_index;
				}else{
					current_bit&=  ~ (1<< bit_index);
				}
				 */
			}

		}
		gathered_bits[thread_index] = current_bits;
		thread_index += blockDim.x * gridDim.x;
		element_index = NUM_ELEMENTS_PER_THREAD_GATHER_BITS * thread_index;
	}
}

gdf_error materialize_valid_ptrs(gdf_column * input, gdf_column * output, gdf_column * row_indices){

	int grid_size, block_size;

	cudaError_t cuda_error = cudaOccupancyMaxPotentialBlockSize(&grid_size,&block_size,gather_bits<unsigned int, int>);
	if(cuda_error != cudaSuccess){
		std::cout<<"Could not get grid and block size!!"<<std::endl;
	}

	gather_bits<<<grid_size, block_size>>>((int *) row_indices->data,(int *) input->valid,(int *) output->valid,row_indices->size);
	cuda_error = cudaGetLastError();
	if(cuda_error != cudaSuccess){
		return GDF_CUDA_ERROR;
	}
	return GDF_SUCCESS;
}

//input and output shoudl be the same time
template <typename ElementIterator, typename IndexIterator>
gdf_error materialize_templated_2(gdf_column * input, gdf_column * output, gdf_column * row_indices){
	materialize_valid_ptrs(input,output,row_indices);

	thrust::detail::normal_iterator<thrust::device_ptr<ElementIterator> > element_iter =
			thrust::detail::make_normal_iterator(thrust::device_pointer_cast((ElementIterator *) input->data));

	thrust::detail::normal_iterator<thrust::device_ptr<IndexIterator> > index_iter =
			thrust::detail::make_normal_iterator(thrust::device_pointer_cast((IndexIterator *) row_indices->data));

	typedef thrust::detail::normal_iterator<thrust::device_ptr<IndexIterator> > IndexNormalIterator;

	thrust::transform_iterator<negative_to_zero<IndexIterator>,IndexNormalIterator> transform_iter = thrust::make_transform_iterator(index_iter,negative_to_zero<IndexIterator>());


	thrust::permutation_iterator<thrust::detail::normal_iterator<thrust::device_ptr<ElementIterator> >,thrust::transform_iterator<negative_to_zero<IndexIterator>,IndexNormalIterator> > iter(element_iter,transform_iter);

	thrust::detail::normal_iterator<thrust::device_ptr<ElementIterator> > output_iter =
			thrust::detail::make_normal_iterator(thrust::device_pointer_cast((ElementIterator *) output->data));;
	thrust::copy(iter,iter + input->size,output_iter);

	return GDF_SUCCESS;
}

template <typename ElementIterator>
gdf_error materialize_templated_1(gdf_column * input, gdf_column * output, gdf_column * row_indices){
	int column_width;
	get_column_byte_width(row_indices, &column_width);
	if(column_width == 1){
		return materialize_templated_2<ElementIterator,int8_t>(input,output,row_indices);
	}else if(column_width == 2){
		return materialize_templated_2<ElementIterator,int16_t>(input,output,row_indices);
	}else if(column_width == 4){
		return materialize_templated_2<ElementIterator,int32_t>(input,output,row_indices);
	}else if(column_width == 8){
		return materialize_templated_2<ElementIterator,int64_t>(input,output,row_indices);
	}

}


gdf_error materialize_column(gdf_column * input, gdf_column * output, gdf_column * row_indices){
	int column_width;
	get_column_byte_width(input, &column_width);
	if(column_width == 1){
		return materialize_templated_1<int8_t>(input,output,row_indices);
	}else if(column_width == 2){
		return materialize_templated_1<int16_t>(input,output,row_indices);
	}else if(column_width == 4){
		return materialize_templated_1<int32_t>(input,output,row_indices);
	}else if(column_width == 8){
		return materialize_templated_1<int64_t>(input,output,row_indices);
	}


}

