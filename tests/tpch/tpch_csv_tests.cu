
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <fstream>

#include <CalciteExpressionParsing.h>
#include <CalciteInterpreter.h>
#include <DataFrame.h>
#include <gtest/gtest.h>
#include <GDFColumn.cuh>
#include <GDFCounter.cuh>
#include <Utils.cuh>

#include "gdf/library/api.h"
using namespace gdf::library;

#include "gdf/library/types.h"

#include <sys/stat.h>

#include "csv_utils.cuh"

using namespace gdf::library;

struct EvaluateQueryTest : public ::testing::Test {


  struct InputTestItem {
    std::string query;
    std::string logicalPlan;
    std::vector<std::string> filePaths;
    std::vector<std::string> tableNames;
    std::vector<std::vector<std::string>> columnNames;
    std::vector<std::vector<const char*>> columnTypes;
    gdf::library::Table resultTable;
  };

  void CHECK_RESULT(gdf::library::Table& computed_solution,
                    gdf::library::Table& reference_solution) {
    computed_solution.print(std::cout);
    reference_solution.print(std::cout);

    for (size_t index = 0; index < reference_solution.size(); index++) {
      const auto& reference_column = reference_solution[index];
      const auto& computed_column = computed_solution[index];
      auto a = reference_column.to_string();
      auto b = computed_column.to_string();
      EXPECT_EQ(a, b);
    }
  }


  virtual void SetUp() {
	std::ofstream outfile("/tmp/customer.psv", std::ofstream::out);
	auto content = 
R"(1|Customer#000000001|IVhzIApeRb ot,c,E|15|25-989-741-2988|711.56|BUILDING|to the even, regular platelets. regular, ironic epitaphs nag e
2|Customer#000000002|XSTf4,NCwDVaWNe6tEgvwfmRchLXak|13|23-768-687-3665|121.65|AUTOMOBILE|l accounts. blithely ironic theodolites integrate boldly: caref
3|Customer#000000003|MG9kdTD2WBHm|1|11-719-748-3364|7498.12|AUTOMOBILE| deposits eat slyly ironic, even instructions. express foxes detect slyly. blithely even accounts abov
4|Customer#000000004|XxVSJsLAGtn|4|14-128-190-5944|2866.83|MACHINERY| requests. final, regular ideas sleep final accou
5|Customer#000000005|KvpyuHCplrB84WgAiGV6sYpZq7Tj|3|13-750-942-6364|794.47|HOUSEHOLD|n accounts will have to unwind. foxes cajole accor
6|Customer#000000006|sKZz0CsnMD7mp4Xd0YrBvx,LREYKUWAh yVn|20|30-114-968-4951|7638.57|AUTOMOBILE|tions. even deposits boost according to the slyly bold packages. final accounts cajole requests. furious
7|Customer#000000007|TcGe5gaZNgVePxU5kRrvXBfkasDTea|18|28-190-982-9759|9561.95|AUTOMOBILE|ainst the ironic, express theodolites. express, even pinto beans among the exp
8|Customer#000000008|I0B10bB0AymmC, 0PrRYBCP1yGJ8xcBPmWhl5|17|27-147-574-9335|6819.74|BUILDING|among the slyly regular theodolites kindle blithely courts. carefully even theodolites haggle slyly along the ide
9|Customer#000000009|xKiAFTjUsCuxfeleNqefumTrjS|8|18-338-906-3675|8324.07|FURNITURE|r theodolites according to the requests wake thinly excuses: pending requests haggle furiousl
10|Customer#000000010|6LrEaV6KR6PLVcgl2ArL Q3rqzLzcT1 v2|5|15-741-346-9870|2753.54|HOUSEHOLD|es regular deposits haggle. fur
11|Customer#000000011|PkWS 3HlXqwTuzrKg633BEi|23|33-464-151-3439|-272.6|BUILDING|ckages. requests sleep slyly. quickly even pinto beans promise above the slyly regular pinto beans. 
12|Customer#000000012|9PWKuhzT4Zr1Q|13|23-791-276-1263|3396.49|HOUSEHOLD| to the carefully final braids. blithely regular requests nag. ironic theodolites boost quickly along
13|Customer#000000013|nsXQu0oVjD7PM659uC3SRSp|3|13-761-547-5974|3857.34|BUILDING|ounts sleep carefully after the close frays. carefully bold notornis use ironic requests. blithely
14|Customer#000000014|KXkletMlL2JQEA |1|11-845-129-3851|5266.3|FURNITURE|, ironic packages across the unus
15|Customer#000000015|YtWggXoOLdwdo7b0y,BZaGUQMLJMX1Y,EC,6Dn|23|33-687-542-7601|2788.52|HOUSEHOLD| platelets. regular deposits detect asymptotes. blithely unusual packages nag slyly at the fluf
16|Customer#000000016|cYiaeMLZSMAOQ2 d0W,|10|20-781-609-3107|4681.03|FURNITURE|kly silent courts. thinly regular theodolites sleep fluffily after 
17|Customer#000000017|izrh 6jdqtp2eqdtbkswDD8SG4SzXruMfIXyR7|2|12-970-682-3487|6.34|AUTOMOBILE|packages wake! blithely even pint
18|Customer#000000018|3txGO AiuFux3zT0Z9NYaFRnZt|6|16-155-215-1315|5494.43|BUILDING|s sleep. carefully even instructions nag furiously alongside of t
19|Customer#000000019|uc,3bHIx84H,wdrmLOjVsiqXCq2tr|18|28-396-526-5053|8914.71|HOUSEHOLD| nag. furiously careful packages are slyly at the accounts. furiously regular in
20|Customer#000000020|JrPk8Pqplj4Ne|22|32-957-234-8742|7603.4|FURNITURE|g alongside of the special excuses-- fluffily enticing packages wake 
21|Customer#000000021|XYmVpr9yAHDEn|8|18-902-614-8344|1428.25|MACHINERY| quickly final accounts integrate blithely furiously u
22|Customer#000000022|QI6p41,FNs5k7RZoCCVPUTkUdYpB|3|13-806-545-9701|591.98|MACHINERY|s nod furiously above the furiously ironic ideas. 
23|Customer#000000023|OdY W13N7Be3OC5MpgfmcYss0Wn6TKT|3|13-312-472-8245|3332.02|HOUSEHOLD|deposits. special deposits cajole slyly. fluffily special deposits about the furiously 
24|Customer#000000024|HXAFgIAyjxtdqwimt13Y3OZO 4xeLe7U8PqG|13|23-127-851-8031|9255.67|MACHINERY|into beans. fluffily final ideas haggle fluffily
25|Customer#000000025|Hp8GyFQgGHFYSilH5tBfe|12|22-603-468-3533|7133.7|FURNITURE|y. accounts sleep ruthlessly according to the regular theodolites. unusual instructions sleep. ironic, final
26|Customer#000000026|8ljrc5ZeMl7UciP|22|32-363-455-4837|5182.05|AUTOMOBILE|c requests use furiously ironic requests. slyly ironic dependencies us
27|Customer#000000027|IS8GIyxpBrLpMT0u7|3|13-137-193-2709|5679.84|BUILDING| about the carefully ironic pinto beans. accoun
28|Customer#000000028|iVyg0daQ,Tha8x2WPWA9m2529m|8|18-774-241-1462|1007.18|FURNITURE| along the regular deposits. furiously final pac
29|Customer#000000029|sJ5adtfyAkCK63df2,vF25zyQMVYE34uh|0|10-773-203-7342|7618.27|FURNITURE|its after the carefully final platelets x-ray against 
30|Customer#000000030|nJDsELGAavU63Jl0c5NKsKfL8rIJQQkQnYL2QJY|1|11-764-165-5076|9321.01|BUILDING|lithely final requests. furiously unusual account
31|Customer#000000031|LUACbO0viaAv6eXOAebryDB xjVst|23|33-197-837-7094|5236.89|HOUSEHOLD|s use among the blithely pending depo
32|Customer#000000032|jD2xZzi UmId,DCtNBLXKj9q0Tlp2iQ6ZcO3J|15|25-430-914-2194|3471.53|BUILDING|cial ideas. final, furious requests across the e
33|Customer#000000033|qFSlMuLucBmx9xnn5ib2csWUweg D|17|27-375-391-1280|-78.56|AUTOMOBILE|s. slyly regular accounts are furiously. carefully pending requests
34|Customer#000000034|Q6G9wZ6dnczmtOx509xgE,M2KV|15|25-344-968-5422|8589.7|HOUSEHOLD|nder against the even, pending accounts. even
35|Customer#000000035|TEjWGE4nBzJL2|17|27-566-888-7431|1228.24|HOUSEHOLD|requests. special, express requests nag slyly furiousl
36|Customer#000000036|3TvCzjuPzpJ0,DdJ8kW5U|21|31-704-669-5769|4987.27|BUILDING|haggle. enticing, quiet platelets grow quickly bold sheaves. carefully regular acc
37|Customer#000000037|7EV4Pwh,3SboctTWt|8|18-385-235-7162|-917.75|FURNITURE|ilent packages are carefully among the deposits. furiousl
38|Customer#000000038|a5Ee5e9568R8RLP 2ap7|12|22-306-880-7212|6345.11|HOUSEHOLD|lar excuses. closely even asymptotes cajole blithely excuses. carefully silent pinto beans sleep carefully fin
39|Customer#000000039|nnbRg,Pvy33dfkorYE FdeZ60|2|12-387-467-6509|6264.31|AUTOMOBILE|tions. slyly silent excuses slee
40|Customer#000000040|gOnGWAyhSV1ofv|3|13-652-915-8939|1335.3|BUILDING|rges impress after the slyly ironic courts. foxes are. blithely 
41|Customer#000000041|IM9mzmyoxeBmvNw8lA7G3Ydska2nkZF|10|20-917-711-4011|270.95|HOUSEHOLD|ly regular accounts hang bold, silent packages. unusual foxes haggle slyly above the special, final depo
42|Customer#000000042|ziSrvyyBke|5|15-416-330-4175|8727.01|BUILDING|ssly according to the pinto beans: carefully special requests across the even, pending accounts wake special
43|Customer#000000043|ouSbjHk8lh5fKX3zGso3ZSIj9Aa3PoaFd|19|29-316-665-2897|9904.28|MACHINERY|ial requests: carefully pending foxes detect quickly. carefully final courts cajole quickly. carefully
44|Customer#000000044|Oi,dOSPwDu4jo4x,,P85E0dmhZGvNtBwi|16|26-190-260-5375|7315.94|AUTOMOBILE|r requests around the unusual, bold a
45|Customer#000000045|4v3OcpFgoOmMG,CbnF,4mdC|9|19-715-298-9917|9983.38|AUTOMOBILE|nto beans haggle slyly alongside of t
46|Customer#000000046|eaTXWWm10L9|6|16-357-681-2007|5744.59|AUTOMOBILE|ctions. accounts sleep furiously even requests. regular, regular accounts cajole blithely around the final pa
47|Customer#000000047|b0UgocSqEW5 gdVbhNT|2|12-427-271-9466|274.58|BUILDING|ions. express, ironic instructions sleep furiously ironic ideas. furi
48|Customer#000000048|0UU iPhBupFvemNB|0|10-508-348-5882|3792.5|BUILDING|re fluffily pending foxes. pending, bold platelets sleep slyly. even platelets cajo
49|Customer#000000049|cNgAeX7Fqrdf7HQN9EwjUa4nxT,68L FKAxzl|10|20-908-631-4424|4573.94|FURNITURE|nusual foxes! fluffily pending packages maintain to the regular 
50|Customer#000000050|9SzDYlkzxByyJ1QeTI o|6|16-658-112-3221|4266.13|MACHINERY|ts. furiously ironic accounts cajole furiously slyly ironic dinos.
51|Customer#000000051|uR,wEaiTvo4|12|22-344-885-4251|855.87|FURNITURE|eposits. furiously regular requests integrate carefully packages. furious
52|Customer#000000052|7 QOqGqqSy9jfV51BC71jcHJSD0|11|21-186-284-5998|5630.28|HOUSEHOLD|ic platelets use evenly even accounts. stealthy theodolites cajole furiou
53|Customer#000000053|HnaxHzTfFTZs8MuCpJyTbZ47Cm4wFOOgib|15|25-168-852-5363|4113.64|HOUSEHOLD|ar accounts are. even foxes are blithely. fluffily pending deposits boost
54|Customer#000000054|,k4vf 5vECGWFy,hosTE,|4|14-776-370-4745|868.9|AUTOMOBILE|sual, silent accounts. furiously express accounts cajole special deposits. final, final accounts use furi
55|Customer#000000055|zIRBR4KNEl HzaiV3a i9n6elrxzDEh8r8pDom|10|20-180-440-8525|4572.11|MACHINERY|ully unusual packages wake bravely bold packages. unusual requests boost deposits! blithely ironic packages ab
56|Customer#000000056|BJYZYJQk4yD5B|10|20-895-685-6920|6530.86|FURNITURE|. notornis wake carefully. carefully fluffy requests are furiously even accounts. slyly expre
57|Customer#000000057|97XYbsuOPRXPWU|21|31-835-306-1650|4151.93|AUTOMOBILE|ove the carefully special packages. even, unusual deposits sleep slyly pend
58|Customer#000000058|g9ap7Dk1Sv9fcXEWjpMYpBZIRUohi T|13|23-244-493-2508|6478.46|HOUSEHOLD|ideas. ironic ideas affix furiously express, final instructions. regular excuses use quickly e
59|Customer#000000059|zLOCP0wh92OtBihgspOGl4|1|11-355-584-3112|3458.6|MACHINERY|ously final packages haggle blithely after the express deposits. furiou
60|Customer#000000060|FyodhjwMChsZmUz7Jz0H|12|22-480-575-5866|2741.87|MACHINERY|latelets. blithely unusual courts boost furiously about the packages. blithely final instruct
61|Customer#000000061|9kndve4EAJxhg3veF BfXr7AqOsT39o gtqjaYE|17|27-626-559-8599|1536.24|FURNITURE|egular packages shall have to impress along the 
62|Customer#000000062|upJK2Dnw13,|7|17-361-978-7059|595.61|MACHINERY|kly special dolphins. pinto beans are slyly. quickly regular accounts are furiously a
63|Customer#000000063|IXRSpVWWZraKII|21|31-952-552-9584|9331.13|AUTOMOBILE|ithely even accounts detect slyly above the fluffily ir
64|Customer#000000064|MbCeGY20kaKK3oalJD,OT|3|13-558-731-7204|-646.64|BUILDING|structions after the quietly ironic theodolites cajole be
65|Customer#000000065|RGT yzQ0y4l0H90P783LG4U95bXQFDRXbWa1sl,X|23|33-733-623-5267|8795.16|AUTOMOBILE|y final foxes serve carefully. theodolites are carefully. pending i
66|Customer#000000066|XbsEqXH1ETbJYYtA1A|22|32-213-373-5094|242.77|HOUSEHOLD|le slyly accounts. carefully silent packages benea
67|Customer#000000067|rfG0cOgtr5W8 xILkwp9fpCS8|9|19-403-114-4356|8166.59|MACHINERY|indle furiously final, even theodo
68|Customer#000000068|o8AibcCRkXvQFh8hF,7o|12|22-918-832-2411|6853.37|HOUSEHOLD| pending pinto beans impress realms. final dependencies 
69|Customer#000000069|Ltx17nO9Wwhtdbe9QZVxNgP98V7xW97uvSH1prEw|9|19-225-978-5670|1709.28|HOUSEHOLD|thely final ideas around the quickly final dependencies affix carefully quickly final theodolites. final accounts c
70|Customer#000000070|mFowIuhnHjp2GjCiYYavkW kUwOjIaTCQ|22|32-828-107-2832|4867.52|FURNITURE|fter the special asymptotes. ideas after the unusual frets cajole quickly regular pinto be
71|Customer#000000071|TlGalgdXWBmMV,6agLyWYDyIz9MKzcY8gl,w6t1B|7|17-710-812-5403|-611.19|HOUSEHOLD|g courts across the regular, final pinto beans are blithely pending ac
72|Customer#000000072|putjlmskxE,zs,HqeIA9Wqu7dhgH5BVCwDwHHcf|2|12-759-144-9689|-362.86|FURNITURE|ithely final foxes sleep always quickly bold accounts. final wat
73|Customer#000000073|8IhIxreu4Ug6tt5mog4|0|10-473-439-3214|4288.5|BUILDING|usual, unusual packages sleep busily along the furiou
74|Customer#000000074|IkJHCA3ZThF7qL7VKcrU nRLl,kylf |4|14-199-862-7209|2764.43|MACHINERY|onic accounts. blithely slow packages would haggle carefully. qui
75|Customer#000000075|Dh 6jZ,cwxWLKQfRKkiGrzv6pm|18|28-247-803-9025|6684.1|AUTOMOBILE| instructions cajole even, even deposits. finally bold deposits use above the even pains. slyl
76|Customer#000000076|m3sbCvjMOHyaOofH,e UkGPtqc4|0|10-349-718-3044|5745.33|FURNITURE|pecial deposits. ironic ideas boost blithely according to the closely ironic theodolites! furiously final deposits n
77|Customer#000000077|4tAE5KdMFGD4byHtXF92vx|17|27-269-357-4674|1738.87|BUILDING|uffily silent requests. carefully ironic asymptotes among the ironic hockey players are carefully bli
78|Customer#000000078|HBOta,ZNqpg3U2cSL0kbrftkPwzX|9|19-960-700-9191|7136.97|FURNITURE|ests. blithely bold pinto beans h
79|Customer#000000079|n5hH2ftkVRwW8idtD,BmM2|15|25-147-850-4166|5121.28|MACHINERY|es. packages haggle furiously. regular, special requests poach after the quickly express ideas. blithely pending re
80|Customer#000000080|K,vtXp8qYB |0|10-267-172-7101|7383.53|FURNITURE|tect among the dependencies. bold accounts engage closely even pinto beans. ca
81|Customer#000000081|SH6lPA7JiiNC6dNTrR|20|30-165-277-3269|2023.71|BUILDING|r packages. fluffily ironic requests cajole fluffily. ironically regular theodolit
82|Customer#000000082|zhG3EZbap4c992Gj3bK,3Ne,Xn|18|28-159-442-5305|9468.34|AUTOMOBILE|s wake. bravely regular accounts are furiously. regula
83|Customer#000000083|HnhTNB5xpnSF20JBH4Ycs6psVnkC3RDf|22|32-817-154-4122|6463.51|BUILDING|ccording to the quickly bold warhorses. final, regular foxes integrate carefully. bold packages nag blithely ev
84|Customer#000000084|lpXz6Fwr9945rnbtMc8PlueilS1WmASr CB|11|21-546-818-3802|5174.71|FURNITURE|ly blithe foxes. special asymptotes haggle blithely against the furiously regular depo
85|Customer#000000085|siRerlDwiolhYR 8FgksoezycLj|5|15-745-585-8219|3386.64|FURNITURE|ronic ideas use above the slowly pendin
86|Customer#000000086|US6EGGHXbTTXPL9SBsxQJsuvy|0|10-677-951-2353|3306.32|HOUSEHOLD|quests. pending dugouts are carefully aroun
87|Customer#000000087|hgGhHVSWQl 6jZ6Ev|23|33-869-884-7053|6327.54|FURNITURE|hely ironic requests integrate according to the ironic accounts. slyly regular pla
88|Customer#000000088|wtkjBN9eyrFuENSMmMFlJ3e7jE5KXcg|16|26-516-273-2566|8031.44|AUTOMOBILE|s are quickly above the quickly ironic instructions; even requests about the carefully final deposi
89|Customer#000000089|dtR, y9JQWUO6FoJExyp8whOU|14|24-394-451-5404|1530.76|FURNITURE|counts are slyly beyond the slyly final accounts. quickly final ideas wake. r
90|Customer#000000090|QxCzH7VxxYUWwfL7|16|26-603-491-1238|7354.23|BUILDING|sly across the furiously even 
91|Customer#000000091|S8OMYFrpHwoNHaGBeuS6E 6zhHGZiprw1b7 q|8|18-239-400-3677|4643.14|AUTOMOBILE|onic accounts. fluffily silent pinto beans boost blithely according to the fluffily exp
92|Customer#000000092|obP PULk2LH LqNF,K9hcbNqnLAkJVsl5xqSrY,|2|12-446-416-8471|1182.91|MACHINERY|. pinto beans hang slyly final deposits. ac
93|Customer#000000093|EHXBr2QGdh|7|17-359-388-5266|2182.52|MACHINERY|press deposits. carefully regular platelets r
94|Customer#000000094|IfVNIN9KtkScJ9dUjK3Pg5gY1aFeaXewwf|9|19-953-499-8833|5500.11|HOUSEHOLD|latelets across the bold, final requests sleep according to the fluffily bold accounts. unusual deposits amon
95|Customer#000000095|EU0xvmWvOmUUn5J,2z85DQyG7QCJ9Xq7|15|25-923-255-2929|5327.38|MACHINERY|ithely. ruthlessly final requests wake slyly alongside of the furiously silent pinto beans. even the
96|Customer#000000096|vWLOrmXhRR|8|18-422-845-1202|6323.92|AUTOMOBILE|press requests believe furiously. carefully final instructions snooze carefully. 
97|Customer#000000097|OApyejbhJG,0Iw3j rd1M|17|27-588-919-5638|2164.48|AUTOMOBILE|haggle slyly. bold, special ideas are blithely above the thinly bold theo
98|Customer#000000098|7yiheXNSpuEAwbswDW|12|22-885-845-6889|-551.37|BUILDING|ages. furiously pending accounts are quickly carefully final foxes: busily pe
99|Customer#000000099|szsrOiPtCHVS97Lt|15|25-515-237-9232|4088.65|HOUSEHOLD|cajole slyly about the regular theodolites! furiously bold requests nag along the pending, regular packages. somas
100|Customer#000000100|fptUABXcmkC5Wx|20|30-749-445-4907|9889.89|FURNITURE|was furiously fluffily quiet deposits. silent, pending requests boost against 
101|Customer#000000101|sMmL2rNeHDltovSm Y|2|12-514-298-3699|7470.96|MACHINERY| sleep. pending packages detect slyly ironic pack
102|Customer#000000102|UAtflJ06 fn9zBfKjInkQZlWtqaA|19|29-324-978-8538|8462.17|BUILDING|ously regular dependencies nag among the furiously express dinos. blithely final
103|Customer#000000103|8KIsQX4LJ7QMsj6DrtFtXu0nUEdV,8a|9|19-216-107-2107|2757.45|BUILDING|furiously pending notornis boost slyly around the blithely ironic ideas? final, even instructions cajole fl
104|Customer#000000104|9mcCK L7rt0SwiYtrbO88DiZS7U d7M|10|20-966-284-8065|-588.38|FURNITURE|rate carefully slyly special pla
105|Customer#000000105|4iSJe4L SPjg7kJj98Yz3z0B|10|20-793-553-6417|9091.82|MACHINERY|l pains cajole even accounts. quietly final instructi
106|Customer#000000106|xGCOEAUjUNG|1|11-751-989-4627|3288.42|MACHINERY|lose slyly. ironic accounts along the evenly regular theodolites wake about the special, final gifts. 
107|Customer#000000107|Zwg64UZ,q7GRqo3zm7P1tZIRshBDz|15|25-336-529-9919|2514.15|AUTOMOBILE|counts cajole slyly. regular requests wake. furiously regular deposits about the blithely final fo
108|Customer#000000108|GPoeEvpKo1|5|15-908-619-7526|2259.38|BUILDING|refully ironic deposits sleep. regular, unusual requests wake slyly
109|Customer#000000109|OOOkYBgCMzgMQXUmkocoLb56rfrdWp2NE2c|16|26-992-422-8153|-716.1|BUILDING|es. fluffily final dependencies sleep along the blithely even pinto beans. final deposits haggle furiously furiou
110|Customer#000000110|mymPfgphaYXNYtk|10|20-893-536-2069|7462.99|AUTOMOBILE|nto beans cajole around the even, final deposits. quickly bold packages according to the furiously regular dept
111|Customer#000000111|CBSbPyOWRorloj2TBvrK9qp9tHBs|22|32-582-283-7528|6505.26|MACHINERY|ly unusual instructions detect fluffily special deposits-- theodolites nag carefully during the ironic dependencies
112|Customer#000000112|RcfgG3bO7QeCnfjqJT1|19|29-233-262-8382|2953.35|FURNITURE|rmanently unusual multipliers. blithely ruthless deposits are furiously along the
113|Customer#000000113|eaOl5UBXIvdY57rglaIzqvfPD,MYfK|12|22-302-930-4756|2912.0|BUILDING|usly regular theodolites boost furiously doggedly pending instructio
114|Customer#000000114|xAt 5f5AlFIU|14|24-805-212-7646|1027.46|FURNITURE|der the carefully express theodolites are after the packages. packages are. bli
115|Customer#000000115|0WFt1IXENmUT2BgbsB0ShVKJZt0HCBCbFl0aHc|8|18-971-699-1843|7508.92|HOUSEHOLD|sits haggle above the carefully ironic theodolite
116|Customer#000000116|yCuVxIgsZ3,qyK2rloThy3u|16|26-632-309-5792|8403.99|BUILDING|as. quickly final sauternes haggle slyly carefully even packages. brave, ironic pinto beans are above the furious
117|Customer#000000117|uNhM,PzsRA3S,5Y Ge5Npuhi|24|34-403-631-3505|3950.83|FURNITURE|affix. instructions are furiously sl
118|Customer#000000118|OVnFuHygK9wx3xpg8|18|28-639-943-7051|3582.37|AUTOMOBILE|uick packages alongside of the furiously final deposits haggle above the fluffily even foxes. blithely dogged dep
119|Customer#000000119|M1ETOIecuvH8DtM0Y0nryXfW|7|17-697-919-8406|3930.35|FURNITURE|express ideas. blithely ironic foxes thrash. special acco
120|Customer#000000120|zBNna00AEInqyO1|12|22-291-534-1571|363.75|MACHINERY| quickly. slyly ironic requests cajole blithely furiously final dependen
121|Customer#000000121|tv nCR2YKupGN73mQudO|17|27-411-990-2959|6428.32|BUILDING|uriously stealthy ideas. carefully final courts use carefully
122|Customer#000000122|yp5slqoNd26lAENZW3a67wSfXA6hTF|3|13-702-694-4520|7865.46|HOUSEHOLD| the special packages hinder blithely around the permanent requests. bold depos
123|Customer#000000123|YsOnaaER8MkvK5cpf4VSlq|5|15-817-151-1168|5897.83|BUILDING|ependencies. regular, ironic requests are fluffily regu
124|Customer#000000124|aTbyVAW5tCd,v09O|18|28-183-750-7809|1842.49|AUTOMOBILE|le fluffily even dependencies. quietly s
125|Customer#000000125|,wSZXdVR xxIIfm9s8ITyLl3kgjT6UC07GY0Y|19|29-261-996-3120|-234.12|FURNITURE|x-ray finally after the packages? regular requests c
126|Customer#000000126|ha4EHmbx3kg DYCsP6DFeUOmavtQlHhcfaqr|22|32-755-914-7592|1001.39|HOUSEHOLD|s about the even instructions boost carefully furiously ironic pearls. ruthless, 
127|Customer#000000127|Xyge4DX2rXKxXyye1Z47LeLVEYMLf4Bfcj|21|31-101-672-2951|9280.71|MACHINERY|ic, unusual theodolites nod silently after the final, ironic instructions: pending r
128|Customer#000000128|AmKUMlJf2NRHcKGmKjLS|4|14-280-874-8044|-986.96|HOUSEHOLD|ing packages integrate across the slyly unusual dugouts. blithely silent ideas sublate carefully. blithely expr
129|Customer#000000129|q7m7rbMM0BpaCdmxloCgBDRCleXsXkdD8kf|7|17-415-148-7416|9127.27|HOUSEHOLD| unusual deposits boost carefully furiously silent ideas. pending accounts cajole slyly across
130|Customer#000000130|RKPx2OfZy0Vn 8wGWZ7F2EAvmMORl1k8iH|9|19-190-993-9281|5073.58|HOUSEHOLD|ix slowly. express packages along the furiously ironic requests integrate daringly deposits. fur
131|Customer#000000131|jyN6lAjb1FtH10rMC,XzlWyCBrg75|11|21-840-210-3572|8595.53|HOUSEHOLD|jole special packages. furiously final dependencies about the furiously speci
132|Customer#000000132|QM5YabAsTLp9|4|14-692-150-9717|162.57|HOUSEHOLD|uickly carefully special theodolites. carefully regular requests against the blithely unusual instructions 
133|Customer#000000133|IMCuXdpIvdkYO92kgDGuyHgojcUs88p|17|27-408-997-8430|2314.67|AUTOMOBILE|t packages. express pinto beans are blithely along the unusual, even theodolites. silent packages use fu
134|Customer#000000134|sUiZ78QCkTQPICKpA9OBzkUp2FM|11|21-200-159-5932|4608.9|BUILDING|yly fluffy foxes boost final ideas. b
135|Customer#000000135|oZK,oC0 fdEpqUML|19|29-399-293-6241|8732.91|FURNITURE| the slyly final accounts. deposits cajole carefully. carefully sly packag
136|Customer#000000136|QoLsJ0v5C1IQbh,DS1|7|17-501-210-4726|-842.39|FURNITURE|ackages sleep ironic, final courts. even requests above the blithely bold requests g
137|Customer#000000137|cdW91p92rlAEHgJafqYyxf1Q|16|26-777-409-5654|7838.3|HOUSEHOLD|carefully regular theodolites use. silent dolphins cajo
138|Customer#000000138|5uyLAeY7HIGZqtu66Yn08f|5|15-394-860-4589|430.59|MACHINERY|ts doze on the busy ideas. regular
139|Customer#000000139|3ElvBwudHKL02732YexGVFVt |9|19-140-352-1403|7897.78|MACHINERY|nstructions. quickly ironic ideas are carefully. bold, 
140|Customer#000000140|XRqEPiKgcETII,iOLDZp5jA|4|14-273-885-6505|9963.15|MACHINERY|ies detect slyly ironic accounts. slyly ironic theodolites hag
141|Customer#000000141|5IW,WROVnikc3l7DwiUDGQNGsLBGOL6Dc0|1|11-936-295-6204|6706.14|FURNITURE|packages nag furiously. carefully unusual accounts snooze according to the fluffily regular pinto beans. slyly spec
142|Customer#000000142|AnJ5lxtLjioClr2khl9pb8NLxG2,|9|19-407-425-2584|2209.81|AUTOMOBILE|. even, express theodolites upo
143|Customer#000000143|681r22uL452zqk 8By7I9o9enQfx0|16|26-314-406-7725|2186.5|MACHINERY|across the blithely unusual requests haggle theodo
144|Customer#000000144|VxYZ3ebhgbltnetaGjNC8qCccjYU05 fePLOno8y|1|11-717-379-4478|6417.31|MACHINERY|ges. slyly regular accounts are slyly. bold, idle reque
145|Customer#000000145|kQjHmt2kcec cy3hfMh969u|13|23-562-444-8454|9748.93|HOUSEHOLD|ests? express, express instructions use. blithely fina
146|Customer#000000146|GdxkdXG9u7iyI1,,y5tq4ZyrcEy|3|13-835-723-3223|3328.68|FURNITURE|ffily regular dinos are slyly unusual requests. slyly specia
147|Customer#000000147|6VvIwbVdmcsMzuu,C84GtBWPaipGfi7DV|18|28-803-187-4335|8071.4|AUTOMOBILE|ress packages above the blithely regular packages sleep fluffily blithely ironic accounts. 
148|Customer#000000148|BhSPlEWGvIJyT9swk vCWE|11|21-562-498-6636|2135.6|HOUSEHOLD|ing to the carefully ironic requests. carefully regular dependencies about the theodolites wake furious
149|Customer#000000149|3byTHCp2mNLPigUrrq|19|29-797-439-6760|8959.65|AUTOMOBILE|al instructions haggle against the slyly bold w
150|Customer#000000150|zeoGShTjCwGPplOWFkLURrh41O0AZ8dwNEEN4 |18|28-328-564-7630|3849.48|MACHINERY|ole blithely among the furiously pending packages. furiously bold ideas wake fluffily ironic idea)";
	outfile <<	content << std::endl;
	outfile.close();

	std::ofstream outfile_nation("/tmp/nation.psv", std::ofstream::out);
	content =
R"(0|ALGERIA|0| haggle. carefully final deposits detect slyly agai
1|ARGENTINA|1|al foxes promise slyly according to the regular accounts. bold requests alon
2|BRAZIL|1|y alongside of the pending deposits. carefully special packages are about the ironic forges. slyly special 
3|CANADA|1|eas hang ironic, silent packages. slyly regular packages are furiously over the tithes. fluffily bold
4|EGYPT|4|y above the carefully unusual theodolites. final dugouts are quickly across the furiously regular d
5|ETHIOPIA|0|ven packages wake quickly. regu
6|FRANCE|3|refully final requests. regular, ironi
7|GERMANY|3|l platelets. regular accounts x-ray: unusual, regular acco
8|INDIA|2|ss excuses cajole slyly across the packages. deposits print aroun
9|INDONESIA|2| slyly express asymptotes. regular deposits haggle slyly. carefully ironic hockey players sleep blithely. carefull
10|IRAN|4|efully alongside of the slyly final dependencies. 
11|IRAQ|4|nic deposits boost atop the quickly final requests? quickly regula
12|JAPAN|2|ously. final, express gifts cajole a
13|JORDAN|4|ic deposits are blithely about the carefully regular pa
14|KENYA|0| pending excuses haggle furiously deposits. pending, express pinto beans wake fluffily past t
15|MOROCCO|0|rns. blithely bold courts among the closely regular packages use furiously bold platelets?
16|MOZAMBIQUE|0|s. ironic, unusual asymptotes wake blithely r
17|PERU|1|platelets. blithely pending dependencies use fluffily across the even pinto beans. carefully silent accoun
18|CHINA|2|c dependencies. furiously express notornis sleep slyly regular accounts. ideas sleep. depos
19|ROMANIA|3|ular asymptotes are about the furious multipliers. express dependencies nag above the ironically ironic account
20|SAUDI ARABIA|4|ts. silent requests haggle. closely express packages sleep across the blithely
21|VIETNAM|2|hely enticingly express accounts. even, final 
22|RUSSIA|3| requests against the platelets use never according to the quickly regular pint
23|UNITED KINGDOM|3|eans boost carefully special requests. accounts are. carefull
24|UNITED STATES|1|y final packages. slow foxes cajole quickly. quickly silent platelets breach ironic accounts. unusual pinto be)";

	outfile_nation <<	content << std::endl;
	outfile_nation.close();

	std::ofstream outfile_region("/tmp/region.psv", std::ofstream::out);
	content =
R"(0|AFRICA|lar deposits. blithely final packages cajole. regular waters are final requests. regular accounts are according to 
1|AMERICA|hs use ironic, even requests. s
2|ASIA|ges. thinly even pinto beans ca
3|EUROPE|ly final courts cajole furiously final excuse
4|MIDDLE EAST|uickly special accounts cajole carefully blithely close requests. carefully final asymptotes haggle furiousl)";
	outfile_region <<	content << std::endl;
	outfile_region.close();
  }
};

// AUTO GENERATED UNIT TESTS
TEST_F(EvaluateQueryTest, TEST_00) {
  auto input = InputTestItem{
      .query =
          "select c_custkey, c_nationkey, c_acctbal from main.customer where "
          "c_custkey < 15",
      .logicalPlan =
          "LogicalProject(c_custkey=[$0], c_nationkey=[$3], c_acctbal=[$5])\n  "
          "LogicalFilter(condition=[<($0, 15)])\n    "
          "LogicalTableScan(table=[[main, customer]])",
      .filePaths = {"/tmp/customer.psv"},
      .tableNames = {"main.customer"},
      .columnNames = {{"c_custkey", "c_name", "c_address", "c_nationkey",
                       "c_phone", "c_acctbal", "c_mktsegment", "c_comment"}},
      .columnTypes = {{"int32", "str", "str", "int32", "int64", "float32",
                       "str", "str"}},
      .resultTable =
          LiteralTableBuilder{
              "ResultSet",
              {{"GDF_INT32", Literals<GDF_INT32>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
                                                 11, 12, 13, 14}},
               {"GDF_INT32", Literals<GDF_INT32>{15, 13, 1, 4, 3, 20, 18, 17, 8,
                                                 5, 23, 13, 3, 1}},
               {"GDF_FLOAT32",
                Literals<GDF_FLOAT32>{711.56, 121.65, 7498.12, 2866.83, 794.47,
                                      7638.57, 9561.95, 6819.74, 8324.07,
                                      2753.54, -272.6, 3396.49, 3857.34,
                                      5266.3}}}}
              .Build()};
  auto logical_plan = input.logicalPlan;
  auto input_tables =
      ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
  auto table_names = input.tableNames;
  auto column_names = input.columnNames;
  std::vector<gdf_column_cpp> outputs;
  gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                 logical_plan, outputs);

  EXPECT_TRUE(err == GDF_SUCCESS);
  auto output_table =
      GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
  CHECK_RESULT(output_table, input.resultTable);
}
TEST_F(EvaluateQueryTest, TEST_01) {
  auto input = InputTestItem{
      .query =
          "select c_custkey, c_nationkey, c_acctbal from main.customer where "
          "c_custkey < 150 and c_nationkey = 5",
      .logicalPlan =
          "LogicalProject(c_custkey=[$0], c_nationkey=[$3], c_acctbal=[$5])\n  "
          "LogicalFilter(condition=[AND(<($0, 150), =($3, 5))])\n    "
          "LogicalTableScan(table=[[main, customer]])",
      .filePaths = {"/tmp/customer.psv"},
      .tableNames = {"main.customer"},
      .columnNames = {{"c_custkey", "c_name", "c_address", "c_nationkey",
                       "c_phone", "c_acctbal", "c_mktsegment", "c_comment"}},
      .columnTypes = {{"int32", "int64", "int64", "int32", "int64", "float32",
                       "int64", "int64"}},
      .resultTable =
          LiteralTableBuilder{
              "ResultSet",
              {{"GDF_INT32", Literals<GDF_INT32>{10, 42, 85, 108, 123, 138}},
               {"GDF_INT32", Literals<GDF_INT32>{5, 5, 5, 5, 5, 5}},
               {"GDF_FLOAT32",
                Literals<GDF_FLOAT32>{2753.54, 8727.01, 3386.64, 2259.38,
                                      5897.83, 430.59}}}}
              .Build()};
  auto logical_plan = input.logicalPlan;
  auto input_tables =
      ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
  auto table_names = input.tableNames;
  auto column_names = input.columnNames;
  std::vector<gdf_column_cpp> outputs;
  gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                 logical_plan, outputs);
  EXPECT_TRUE(err == GDF_SUCCESS);
  auto output_table =
      GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
  CHECK_RESULT(output_table, input.resultTable);
}


TEST_F(EvaluateQueryTest, TEST_NULL_BINARY) {
  auto input = InputTestItem{
      .query =
          "SELECT n.n_nationkey + 1, n.n_regionkey from main.nation AS n INNER JOIN main.region AS r ON n.n_regionkey = r.r_regionkey and n.n_nationkey = 5",
      .logicalPlan =
          "LogicalProject(EXPR$0=[$1], n_regionkey=[$0])\n"
          "  LogicalJoin(condition=[AND(=($0, $3), $2)], joinType=[inner])\n"
          "    LogicalProject(n_regionkey=[$2], +=[+($0, 1)], ==[=($0, 5)])\n"
    	  "      LogicalFilter(condition=[=($0, 5)])\n"
    	  "        LogicalTableScan(table=[[main, nation]])\n"
    	  "    LogicalProject(r_regionkey=[$0])\n"
          "      LogicalTableScan(table=[[main, region]])",
      .filePaths = {"/tmp/nation.psv","/tmp/region.psv"},
      .tableNames = {"main.nation", "main.region"},
      .columnNames = {{"n_nationkey", "n_name","n_regionkey", "n_comment"},{"r_regionkey","r_name","r_comment"}},
      .columnTypes = {{"int32", "int64", "int32", "int64"},{"int32", "int64", "int64"}},
      .resultTable =
          LiteralTableBuilder{
              "ResultSet",
              {{"EXPR$0", Literals<GDF_INT32>{6}},
               {"n_regionkey", Literals<GDF_INT32>{0}},
              }}
              .Build()};
  auto logical_plan = input.logicalPlan;
  auto input_tables =
      ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
  GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build().print(std::cout);
  GdfColumnCppsTableBuilder{"input_table", input_tables[1]}.Build().print(std::cout);

  auto table_names = input.tableNames;
  auto column_names = input.columnNames;
  std::vector<gdf_column_cpp> outputs;
  gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                 logical_plan, outputs);

  EXPECT_TRUE(err == GDF_SUCCESS);
  auto output_table =
      GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
  CHECK_RESULT(output_table, input.resultTable);
}




TEST_F(EvaluateQueryTest, TEST_NULL_OUTER_JOIN) {
  auto input = InputTestItem{
      .query =
          "SELECT n.n_nationkey, n.n_regionkey, n.n_nationkey + n.n_regionkey  from main.nation AS n INNER JOIN main.region AS r ON n.n_regionkey = r.r_regionkey and n.n_nationkey < 10 order by n.n_nationkey",
      .logicalPlan =
              "LogicalSort(sort0=[$0], dir0=[ASC])\n  "
    		  "  LogicalProject(n_nationkey=[$0], r_regionkey=[$1], EXPR$2=[+($0, $1)])\n"
    		  "    LogicalJoin(condition=[=($0, $1)], joinType=[left])\n"
    		  "      LogicalProject(n_nationkey=[$0])\n"
    		  "        LogicalFilter(condition=[<($0, 10)])\n"
    		  "          LogicalTableScan(table=[[main, nation]])\n"
    		  "      LogicalProject(r_regionkey=[$0])\n"
    		  "        LogicalTableScan(table=[[main, region]])\n",
      .filePaths = {"/tmp/nation.psv","/tmp/region.psv"},
      .tableNames = {"main.nation", "main.region"},
      .columnNames = {{"n_nationkey", "n_name","n_regionkey", "n_comment"},{"r_regionkey","r_name","r_comment"}},
      .columnTypes = {{"int32", "int64", "int32", "int64"},{"int32", "int64", "int64"}},
      .resultTable =
          LiteralTableBuilder{
              "ResultSet",
              {{"n_nationkey", Literals<GDF_INT32>{0,1,2,3,4,5,6,7,8,9}},
              {"r_regionkey", Literals<GDF_INT32>{Literals<GDF_INT32>::vector{0,1,2,3,4,0,0,0,0,0}, Literals<GDF_INT32>::bool_vector{1, 1, 1, 1, 1, 0, 0, 0, 0, 0}}},
              {"EXPR$2", Literals<GDF_INT32>{Literals<GDF_INT32>::vector{0,2,4,6,8,0,0,0,0,0}, Literals<GDF_INT32>::bool_vector{1, 1, 1, 1, 1, 0, 0, 0, 0, 0}}},
              }}
              .Build()};
  auto logical_plan = input.logicalPlan;
  auto input_tables =
      ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
  GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build().print(std::cout);
  GdfColumnCppsTableBuilder{"input_table", input_tables[1]}.Build().print(std::cout);

  auto table_names = input.tableNames;
  auto column_names = input.columnNames;
  std::vector<gdf_column_cpp> outputs;
  gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                 logical_plan, outputs);
  std::cout<<"null count is "<<outputs[2].null_count()<<std::endl;
  EXPECT_TRUE(err == GDF_SUCCESS);
  auto output_table =
      GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
  CHECK_RESULT(output_table, input.resultTable);
}


TEST_F(EvaluateQueryTest, TEST_NULL_OUTER_JOIN_2) {
  auto input = InputTestItem{
      .query =
          "select n.n_nationkey, r.r_regionkey from dfs.tmp.`nation` as n left outer join dfs.tmp.`region` as r on n.n_regionkey = r.r_regionkey where n.n_nationkey < 10 and n.n_nationkey > 5",
      .logicalPlan =
    		  "LogicalProject(n_nationkey=[$0], r_regionkey=[$4])\n"
    		  "  LogicalJoin(condition=[=($2, $4)], joinType=[left])\n"
    		  "    LogicalFilter(condition=[AND(<($0, 10), >=($0, 5))])\n"
    		  "      LogicalTableScan(table=[[main, nation]])\n"
    		  "    LogicalTableScan(table=[[main, region]])",
      .filePaths = {"/tmp/nation.psv","/tmp/region.psv"},
      .tableNames = {"main.nation", "main.region"},
      .columnNames = {{"n_nationkey", "n_name","n_regionkey", "n_comment"},{"r_regionkey","r_name","r_comment"}},
      .columnTypes = {{"int32", "int64", "int32", "int64"},{"int32", "int64", "int64"}},
      .resultTable =
          LiteralTableBuilder{
              "ResultSet",
              {{"n_nationkey", Literals<GDF_INT32>{5,6,7,8,9}},
              {"r_regionkey", Literals<GDF_INT32>{Literals<GDF_INT32>::vector{0,3,3,2,2}, Literals<GDF_INT32>::bool_vector{1, 1, 1, 1, 1}}},
              }}
              .Build()};
  auto logical_plan = input.logicalPlan;
  auto input_tables =
      ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
  GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build().print(std::cout);
  GdfColumnCppsTableBuilder{"input_table", input_tables[1]}.Build().print(std::cout);

  auto table_names = input.tableNames;
  auto column_names = input.columnNames;
  std::vector<gdf_column_cpp> outputs;
  gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                 logical_plan, outputs);
  std::cout<<"null count is "<<outputs[1].null_count()<<std::endl;
  EXPECT_TRUE(err == GDF_SUCCESS);
  auto output_table =
      GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
  CHECK_RESULT(output_table, input.resultTable);
}



        TEST_F(EvaluateQueryTest, TEST_NULL_TRANSFORM_AGGREGATIONS) {
          auto input = InputTestItem{
              .query =
                  "select count(c_custkey) + sum(c_acctbal) + avg(c_acctbal), min(c_custkey) - max(c_nationkey), c_nationkey * 2 as key from main.customer where  c_nationkey * 2 < 40 group by  c_nationkey * 2 order by key",
              .logicalPlan =
                      "LogicalSort(sort0=[$2], dir0=[ASC])\n  "
            		  "  LogicalProject(EXPR$0=[+(+($1, $2), $3)], EXPR$1=[-($4, $5)], key=[$0])\n"
            		  "    LogicalAggregate(group=[{0}], agg#0=[COUNT($1)], agg#1=[SUM($2)], agg#2=[AVG($2)], agg#3=[MIN($1)], agg#4=[MAX($3)])\n"
            		  "      LogicalProject(key=[*($3, 2)], c_custkey=[$0], c_acctbal=[$5], c_nationkey=[$3])\n"
            		  "        LogicalFilter(condition=[<(*($3, 2), 40)])\n"
            		  "          LogicalTableScan(table=[[main, customer]])",
            	      .filePaths = {"/tmp/customer.psv"},
            	      .tableNames = {"main.customer"},
            	      .columnNames = {{"c_custkey", "c_name", "c_address", "c_nationkey",
            	                       "c_phone", "c_acctbal", "c_mktsegment", "c_comment"}},
            	      .columnTypes = {{"int32", "int64", "int64", "int32", "int64", "float32",
            	                       "int64", "int64"}},
              .resultTable =
                  LiteralTableBuilder{
                      "ResultSet",
                      {{"EXPR$0", Literals<GDF_FLOAT32>{37496.2,47956.6,17314.9,29051.7,18251.4,27370.2, 20676.5,16785.2, 32370.1, 56047.8,41177.7,31379.0, 29994.1,34806.4, 3839.33,
                      38188.1, 46194.8,24929.0,58479.7,45247.3}},
                      {"EXPR$1", Literals<GDF_FLOAT32>{29,2,15,2,0,5,12,55,1,36,6,41,13,-11,75,-14,28,-9,-11,24}},
                      {"key", Literals<GDF_FLOAT32>{0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38}},
                      }}
                      .Build()};
          auto logical_plan = input.logicalPlan;
          auto input_tables =
              ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
          GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build().print(std::cout);
          auto table_names = input.tableNames;
          auto column_names = input.columnNames;
          std::vector<gdf_column_cpp> outputs;
          gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                         logical_plan, outputs);
          std::cout<<"null count is "<<outputs[2].null_count()<<std::endl;
          EXPECT_TRUE(err == GDF_SUCCESS);
          auto output_table =
              GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
          CHECK_RESULT(output_table, input.resultTable);
        }

        TEST_F(EvaluateQueryTest, TEST_CUSTOMER_1_GB) {

           //we are asuming the user has wget
         // int download_status = system ("wget -O /tmp/customer.tbl 'https://drive.google.com/a/blazingdb.com/uc?authuser=1&id=1I4pGhK0nw4Gw-zI7PsB6sLm0Sya5f9Cq&export=download'");
          //EXPECT_TRUE(download_status == 0);
          auto input = InputTestItem{
                    .query =
                        "select c_acctbal + 3 as c_acctbal_new from customer where c_acctbal > 1000",
                    .logicalPlan =
                        "LogicalProject(EXPR$0=[+($5, 3)])\n"
                        "  LogicalFilter(condition=[>($5, 1000)])\n"
                        "    LogicalTableScan(table=[[main, customer]])",
                          .filePaths = {"/tmp/customer.tbl"},
                          .tableNames = {"main.customer"},
                          .columnNames = {{"c_custkey", "c_name", "c_address", "c_nationkey",
                                           "c_phone", "c_acctbal", "c_mktsegment", "c_comment"}},
                          .columnTypes = {{"int32", "int64", "int64", "int32", "int64", "float32",
                                           "int64", "int64"}},
                    .resultTable =
                        LiteralTableBuilder{
                            "ResultSet",
                            {{"EXPR$0", Literals<GDF_FLOAT32>{37496.2,47956.6,17314.9,29051.7,18251.4,27370.2, 20676.5,16785.2, 32370.1, 56047.8,41177.7,31379.0, 29994.1,34806.4, 3839.33,
                            38188.1, 46194.8,24929.0,58479.7,45247.3}},
                            {"EXPR$1", Literals<GDF_FLOAT32>{29,2,15,2,0,5,12,55,1,36,6,41,13,-11,75,-14,28,-9,-11,24}},
                            {"key", Literals<GDF_FLOAT32>{0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38}},
                            }}
                            .Build()};
                auto logical_plan = input.logicalPlan;
                auto input_tables =
                    ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
                GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build();
                auto table_names = input.tableNames;
                auto column_names = input.columnNames;
                std::vector<gdf_column_cpp> outputs;
                gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                               logical_plan, outputs);
                std::cout<<"null count is "<<outputs[0].null_count()<<std::endl;
                std::cout<<"size is "<<outputs[0].size()<<std::endl;

                 EXPECT_TRUE(err == GDF_SUCCESS);
                auto output_table =
                    GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
             //   CHECK_RESULT(output_table, input.resultTable);
              }



        TEST_F(EvaluateQueryTest, TEST_CUSTOMER_1_GB_COMPLEX) {

           //we are asuming the user has wget
         // int download_status = system ("wget -O /tmp/customer.tbl 'https://drive.google.com/a/blazingdb.com/uc?authuser=1&id=1I4pGhK0nw4Gw-zI7PsB6sLm0Sya5f9Cq&export=download'");
          //EXPECT_TRUE(download_status == 0);
          auto input = InputTestItem{
                    .query =
                        "select c_custkey, c_nationkey, c_acctbal from main.customer where c_custkey < 150 and c_nationkey = 5 or c_custkey = 200 or c_nationkey >= 10 or c_acctbal <= 500",
                    .logicalPlan =
                        "LogicalProject(c_custkey=[$0], c_nationkey=[$3], c_acctbal=[$5])\n"
                        "  LogicalFilter(condition=[OR(AND(<($0, 150), =($3, 5)), =($0, 200), >=($3, 10), <=($5, 500))])\n"
                        "    LogicalTableScan(table=[[main, customer]])",
                          .filePaths = {"/tmp/customer.tbl"},
                          .tableNames = {"main.customer"},
                          .columnNames = {{"c_custkey", "c_name", "c_address", "c_nationkey",
                                           "c_phone", "c_acctbal", "c_mktsegment", "c_comment"}},
                          .columnTypes = {{"int32", "int64", "int64", "int32", "int64", "float32",
                                           "int64", "int64"}},
                    .resultTable =
                        LiteralTableBuilder{
                            "ResultSet",
                            {{"EXPR$0", Literals<GDF_FLOAT32>{37496.2,47956.6,17314.9,29051.7,18251.4,27370.2, 20676.5,16785.2, 32370.1, 56047.8,41177.7,31379.0, 29994.1,34806.4, 3839.33,
                            38188.1, 46194.8,24929.0,58479.7,45247.3}},
                            {"EXPR$1", Literals<GDF_FLOAT32>{29,2,15,2,0,5,12,55,1,36,6,41,13,-11,75,-14,28,-9,-11,24}},
                            {"key", Literals<GDF_FLOAT32>{0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38}},
                            }}
                            .Build()};
                auto logical_plan = input.logicalPlan;
                auto input_tables =
                    ToBlazingFrame(input.filePaths, input.columnNames, input.columnTypes);
                GdfColumnCppsTableBuilder{"input_table", input_tables[0]}.Build();
                auto table_names = input.tableNames;
                auto column_names = input.columnNames;
                std::vector<gdf_column_cpp> outputs;
                gdf_error err = evaluate_query(input_tables, table_names, column_names,
                                               logical_plan, outputs);
                std::cout<<"null count is "<<outputs[0].null_count()<<std::endl;
                std::cout<<"size is "<<outputs[0].size()<<std::endl;

                 EXPECT_TRUE(err == GDF_SUCCESS);
                auto output_table =
                    GdfColumnCppsTableBuilder{"output_table", outputs}.Build();
             //   CHECK_RESULT(output_table, input.resultTable);
              }
