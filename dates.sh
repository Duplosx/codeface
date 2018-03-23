## UPDATE DATE COLUMN IN RELEASE_TIMELINE
#
# 1. generate a list of tags/hashes with the following MySQL statement
#    (after adapting it to your project):
#
# set @project = "zeppelin";
# set @tagging = "proximity";
# set @projectId = (
#     SELECT id FROM project
#     WHERE name = CONCAT(@project, "_", @tagging)
#     LIMIT 1
# );
# SELECT @projectId;
# SELECT tag FROM release_timeline
# WHERE
#   projectId = @projectId
#   AND type = "release"
# ORDER BY id;
#
#
# 2. set $projectId below (Line 29) to the result of the first query and
#    set $revs below (Line 30+) to the result of the second query.
#
# 3. run this very script in the project repository (NOT in VM!).
#
# 4. run the MySQL queries written to stdout.
#

projectId="53"
revs="ec716cf6e8725dc456db42d11a1972aa78d9de91
99109eebb2e31be24764d41b22bb71ae4e08c19d
150ed37f85a79cb73920454b20e8952fb9510285
6907119b267c4d352eec28a098f2b43cc72a3c49
9c6ff672db07bdaa2f4272c72bfc5289bb6eb82e
a29446930745de80f08148a703ea635b830332b8
666d67f1c09c5cbe767cdaffe5691fbd79526133
94eb55b4d752144172fcec391fa4a4fe7d9a309f
4ca8466ab3d2c3bacee957ecf62b4e54f86820d7
cbef1be485329357f9540e1efb64e5bd5bdcf792
e4ff4c03536999d824c2f3b60859c156dc592a85
39417c073b6d5d6d206ea021f0d68aeb3c81f859
0e719dff54e2397b94a7a2011331646ad4094fbc
47b193151bb762998cc2ae5e4953505f07cb76a2
9bf56d9f64fa439bfb394a21da0b43009cfb8eaa
0d5914af17a17d6bbe3d616a6e98ae938c9283e6
8194a5e0af0e1b926b27ea9e0d12bdf9d0e43b4b
71d130521605cb7dcdb80fb18748ffcd87294ed5
23c5cac8245aea16bfc0568cf2e5c2ae6dfd0e6d
d07c70a6dc32d3d2668198b2e4c10c57602f8ab8"

for i in $revs; do
    d=$(TZ=UTC git log --date=format-local:'%Y-%m-%d %H:%M:%S' --format=%ad -1 $i)
    echo "\
UPDATE release_timeline \
SET date = '$d' \
WHERE projectId = '$projectId' \
AND type = 'release'
AND tag = '$i';"
done
