#include <gtest/gtest.h>
#include <sys/stat.h>

#include "gdf/library/csv.h"
#include "gdf/library/table.h"
#include "gdf/library/table_group.h"
#include "gdf/library/types.h"

#include <gdf/cffi/functions.h>
#include <gdf/gdf.h>
using namespace gdf::library;

TEST(UtilsTest, TableBuilder)
{
  Table t = TableBuilder{
    "emps",
    {
      { "x", [](Index i) -> DType<GDF_FLOAT64> { return i / 10.0; } },
      { "y", [](Index i) -> DType<GDF_UINT64> { return i * 1000; } },
    }
  }
              .Build(10);

  for (std::size_t i = 0; i < 10; i++) {
    EXPECT_EQ(i * 1000, t[1][i].get<GDF_UINT64>());
  }

  for (std::size_t i = 0; i < 10; i++) {
    EXPECT_EQ(i / 10.0, t[0][i].get<GDF_FLOAT64>());
  }
  t.print(std::cout);
}

TEST(UtilsTest, FrameFromTableGroup)
{
  auto g = TableGroupBuilder{
    { "emps",
      {
        { "x", [](Index i) -> DType<GDF_FLOAT64> { return i / 10.0; } },
        { "y", [](Index i) -> DType<GDF_UINT64> { return i * 1000; } },
      } },
    { "emps",
      {
        { "x", [](Index i) -> DType<GDF_FLOAT64> { return i / 100.0; } },
        { "y", [](Index i) -> DType<GDF_UINT64> { return i * 10000; } },
      } }
  }
             .Build({ 10, 20 });

  g[0].print(std::cout);
  g[1].print(std::cout);

  BlazingFrame frame = g.ToBlazingFrame();

  auto hostVector = HostVectorFrom<GDF_UINT64>(frame[1][1]);

  for (std::size_t i = 0; i < 20; i++) {
    EXPECT_EQ(i * 10000, hostVector[i]);
  }
}

TEST(UtilsTest, TableFromLiterals)
{
  auto t = LiteralTableBuilder{ .name = "emps",
    .columns = {
      {
        .name = "x",
        .values = Literals<GDF_FLOAT64>{ 1, 3, 5, 7, 9 },
      },
      {
        .name = "y",
        .values = Literals<GDF_INT64>{ 0, 2, 4, 6, 8 },
      },
    } }
             .Build();

  for (std::size_t i = 0; i < 5; i++) {
    EXPECT_EQ(2 * i, t[1][i].get<GDF_INT64>());
    EXPECT_EQ(2 * i + 1.0, t[0][i].get<GDF_FLOAT64>());
  }

  using VTableBuilder = gdf::library::TableRowBuilder<int8_t, double, int32_t, int64_t>;
  using DataTuple = VTableBuilder::DataTuple;

  gdf::library::Table table = VTableBuilder{
    .name = "emps",
    .headers = { "Id", "Weight", "Age", "Name" },
    .rows = {
      DataTuple{ 'a', 180.2, 40, 100L },
      DataTuple{ 'b', 175.3, 38, 200L },
      DataTuple{ 'c', 140.3, 27, 300L },
    },
  }
                                .Build();

  table.print(std::cout);
}

TEST(UtilsTest, FrameFromGdfColumnsCpps)
{
  auto t = LiteralTableBuilder{ .name = "emps",
    .columns = {
      {
        .name = "x",
        .values = Literals<GDF_FLOAT64>{ 1, 3, 5, 7, 9 },
      },
      {
        .name = "y",
        .values = Literals<GDF_INT64>{ 0, 2, 4, 6, 8 },
      },
    } }
             .Build();

  auto u = GdfColumnCppsTableBuilder{ "emps", t.ToGdfColumnCpps() }.Build();

  for (std::size_t i = 0; i < 5; i++) {
    EXPECT_EQ(2 * i, u[1][i].get<GDF_INT64>());
    EXPECT_EQ(2 * i + 1.0, u[0][i].get<GDF_FLOAT64>());
  }

  EXPECT_EQ(t, u);
}

// TEST(UtilsTest, CSVReaderForCustomerFile)
// {
//   io::CSVReader<8> in("/home/aocsa/blazingdb/tpch/1mb/customer.psv");
//   std::vector<std::string> columnNames = { "c_custkey", "c_nationkey", "c_acctbal" };
//   //  std::vector<std::string> columnTypes =  {GDF_INT32, GDF_INT32, GDF_FLOAT32};
//   using VTableBuilder = gdf::library::TableRowBuilder<int32_t, int32_t, float>;
//   using DataTuple = VTableBuilder::DataTuple;
//   std::vector<DataTuple> rows;
//   int c_custkey;
//   std::string c_name;
//   std::string c_address;
//   int c_nationkey;
//   std::string c_phone;
//   float c_acctbal;
//   std::string c_mktsegment;
//   std::string c_comment;
//   while (in.read_row(c_custkey, c_name, c_address, c_nationkey, c_phone, c_acctbal, c_mktsegment, c_comment)) {
//     // do stuff with the data
//     rows.push_back(DataTuple{ c_custkey, c_nationkey, c_acctbal });
//   }
//   gdf::library::Table table = VTableBuilder{
//     .name = "customer",
//     .headers = columnNames,
//     .rows = rows,
//   }.Build();
//   table.print(std::cout);
// }
