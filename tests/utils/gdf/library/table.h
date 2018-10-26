#pragma once

#include <cassert>
#include <cmath>
#include <iomanip>
#include <ios>
#include <iostream>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#include "any.h"
#include "column.h"
#include "gdf/gdf.h"
#include "vector.h"

namespace gdf {
namespace library {

class Table {
public:
  Table() = default;  //! \deprecated

  Table &operator=(const Table &) = default;  //! \deprecated

  Table(const std::string &                     name,
        std::vector<std::shared_ptr<Column> > &&columns)
    : name_{name}, columns_{std::move(columns)} {}

  const Column &operator[](const std::size_t i) const { return *columns_[i]; }

  std::vector<gdf_column_cpp> ToGdfColumnCpps() const;

  size_t num_columns() const { return columns_.size(); }

  size_t num_rows() const {
    return columns_[0]->size();  //@todo check and assert this
  }

  template <typename StreamType>
  void print(StreamType &stream) const {
    _size_columns();
    unsigned int cell_padding = 1;
    // Start computing the total width
    // First - we will have num_columns() + 1 "|" characters
    unsigned int total_width = num_columns() + 1;

    // Now add in the size of each colum
    for (auto &col_size : column_sizes_)
      total_width += col_size + (2 * cell_padding);

    // Print out the top line
    stream << std::string(total_width, '-') << "\n";

    std::vector<std::string> headers;
    for (unsigned int i = 0; i < num_columns(); i++)
      headers.push_back(this->columns_[i]->name());

    // Print out the headers
    stream << "|";
    for (unsigned int i = 0; i < num_columns(); i++) {
      // Must find the center of the column
      auto half = column_sizes_[i] / 2;
      half -= headers[i].size() / 2;

      stream << std::string(cell_padding, ' ') << std::setw(column_sizes_[i])
             << std::left << std::string(half, ' ') + headers[i]
             << std::string(cell_padding, ' ') << "|";
    }
    stream << "\n";

    // Print out the line below the header
    stream << std::string(total_width, '-') << "\n";

    // Now print the rows of the VTable
    for (int i = 0; i < num_rows(); i++) {
      stream << "|";

      for (int j = 0; j < num_columns(); j++) {
        stream << std::string(cell_padding, ' ') << std::setw(column_sizes_[j])
               << columns_[j]->get_as_str(i) << std::string(cell_padding, ' ')
               << "|";
      }
      stream << "\n";
    }

    // Print out the line below the header
    stream << std::string(total_width, '-') << "\n";
  }

protected:
  void _size_columns() const {
    column_sizes_.resize(num_columns());

    // Temporary for querying each row
    std::vector<unsigned int> column_sizes(num_columns());

    // Start with the size of the headers
    for (unsigned int i = 0; i < num_columns(); i++)
      column_sizes_[i] = this->columns_[i]->name().size();
  }

private:
  std::string                           name_;
  std::vector<std::shared_ptr<Column> > columns_;
  mutable std::vector<unsigned int>     column_sizes_;
};

std::vector<gdf_column_cpp> Table::ToGdfColumnCpps() const {
  std::vector<gdf_column_cpp> gdfColumnsCpps;
  gdfColumnsCpps.resize(columns_.size());
  std::transform(columns_.cbegin(),
                 columns_.cend(),
                 gdfColumnsCpps.begin(),
                 [](const std::shared_ptr<Column> &column) {
                   return column->ToGdfColumnCpp();
                 });
  return gdfColumnsCpps;
}

class TableBuilder {
public:
  TableBuilder(const std::string &&name, std::vector<ColumnBuilder> builders)
    : name_{std::move(name)}, builders_{builders} {}

  Table build(const std::size_t length) {  //! \deprecated
    return Build(length);
  }

  Table Build(const std::size_t length) const {
    std::vector<std::shared_ptr<Column> > columns;
    columns.resize(builders_.size());
    std::transform(std::begin(builders_),
                   std::end(builders_),
                   columns.begin(),
                   [length](const ColumnBuilder &builder) {
                     return std::move(builder.Build(length));
                   });
    return Table(name_, std::move(columns));
  }

  Table Build(const std::vector<std::size_t> &lengths) const {
    std::vector<std::shared_ptr<Column> > columns;
    columns.resize(builders_.size());
    std::transform(
      builders_.cbegin(),
      builders_.cend(),
      columns.begin(),
      [this, lengths](const ColumnBuilder &builder) {
        return std::move(builder.Build(lengths[std::distance(
          builders_.cbegin(),
          static_cast<std::vector<ColumnBuilder>::const_iterator>(&builder))]));
      });
    return Table(name_, std::move(columns));
  }

private:
  const std::string          name_;
  std::vector<ColumnBuilder> builders_;
};

class LiteralTableBuilder : public TableBuilder {
public:
  LiteralTableBuilder(const std::string &&                        name,
                      std::initializer_list<LiteralColumnBuilder> builders)
    : builders_{builders}, TableBuilder{std::forward<const std::string>(name),
                                        ColumnBuildersFrom(builders)} {
    lengths_.resize(builders.size());
    std::transform(builders.begin(),
                   builders.end(),
                   lengths_.begin(),
                   [](const LiteralColumnBuilder &literalBuilder) {
                     return literalBuilder.length();
                   });
  }

  Table Build() const { return TableBuilder::Build(lengths_); }

private:
  static std::vector<ColumnBuilder> ColumnBuildersFrom(
    std::initializer_list<LiteralColumnBuilder> &literalBuilders) {
    std::vector<ColumnBuilder> builders;
    builders.resize(literalBuilders.size());
    std::transform(literalBuilders.begin(),
                   literalBuilders.end(),
                   builders.begin(),
                   [](const LiteralColumnBuilder &literalBuilder) {
                     return literalBuilder;
                   });
    return builders;
  }

  std::initializer_list<LiteralColumnBuilder> builders_;
  std::vector<std::size_t>                    lengths_;
};

}  // namespace library
}  // namespace gdf
