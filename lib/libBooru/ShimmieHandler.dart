import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'dart:async';
import 'BooruHandler.dart';
import 'BooruItem.dart';
import 'Booru.dart';
import 'package:LoliSnatcher/Tools.dart';
/**
 * Booru Handler for the Shimmie engine
 */
class ShimmieHandler extends BooruHandler{
  bool tagSearchEnabled = false;
  // Dart constructors are weird so it has to call super with the args
  ShimmieHandler(Booru booru,int limit) : super(booru,limit);
  /**
   * This function will call a http get request using the tags and pagenumber parsed to it
   * it will then create a list of booruItems
   */
  Future Search(String tags,int pageNum) async{
    isActive = true;
    hasSizeData = true;
    int length = fetched.length;
    if(tags == " " || tags == ""){
      tags="*";
    }
    // if(this.pageNum == pageNum){
    //   return fetched;
    // }
    this.pageNum = pageNum;
    if (prevTags != tags){
      fetched = [];
    }
    String url = makeURL(tags);
    print(url);
    try {
      Uri uri = Uri.parse(url);
      final response = await http.get(uri,headers: {"Accept": "application/xml",  "user-agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0"});
      // 200 is the success http response code
      if (response.statusCode == 200) {
        print(response.body);
        var parsedResponse = xml.parse(response.body);
        /**
         * This creates a list of xml elements 'post' to extract only the post elements which contain
         * all the data needed about each image
         */
        var posts = parsedResponse.findAllElements('post');
        if (posts.length < 1){
          posts = parsedResponse.findAllElements('tag');
        }
        // Create a BooruItem for each post in the list
        for (int i =0; i < posts.length; i++){
          var current = posts.elementAt(i);
          /**
           * Add a new booruitem to the list .getAttribute will get the data assigned to a particular tag in the xml object
           */
          if (current.getAttribute("file_url") != null){
            String preURL = '';
            if (booru.baseURL!.contains("https://whyneko.com/booru")){
              // special case for whyneko
              preURL = booru.baseURL!.split("/booru")[0];
            }

            String dateString = current.getAttribute("date").toString();
            fetched.add(BooruItem(
              fileURL: preURL + current.getAttribute("file_url")!,
              sampleURL: preURL + current.getAttribute("file_url")!,
              thumbnailURL: preURL + current.getAttribute("preview_url")!,
              tagsList: current.getAttribute("tags")!.split(" "),
              postURL: makePostURL(current.getAttribute("id")!),
              fileWidth: double.tryParse(current.getAttribute('width') ?? '') ?? null,
              fileHeight: double.tryParse(current.getAttribute('height') ?? '') ?? null,
              previewWidth: double.tryParse(current.getAttribute('preview_width') ?? '') ?? null,
              previewHeight: double.tryParse(current.getAttribute('preview_height') ?? '') ?? null,
              serverId: current.getAttribute("id"),
              score: current.getAttribute("score"),
              sources: [current.getAttribute("source") ?? ''],
              md5String: current.getAttribute("md5"),
              postDate: dateString.substring(0, dateString.length-3), // 2021-06-18 04:37:31.471007 // microseconds?
              postDateFormat: 'yyyy-MM-dd HH:mm:ss.SSSSSS'
            ));
          }
              
          if(dbHandler!.db != null){
            setTrackedValues(fetched.length - 1);
          }
        }
        prevTags = tags;
        if (fetched.length == length){locked = true;}
        isActive = false;
        return fetched;
      } else {
        print(response.statusCode);
      }
    } catch(e) {
      print(e);
      isActive = false;
      return fetched;
    }

  }
  // This will create a url to goto the images page in the browser
  String makePostURL(String id){
    return "${booru.baseURL}/post/view/$id";
  }
  // This will create a url for the http request
  String makeURL(String tags){
    return "${booru.baseURL}/api/danbooru/find_posts/index.xml?tags=$tags&limit=${limit.toString()}&page=${pageNum.toString()}";
  }


  String makeTagURL(String input){
    if (booru.baseURL!.contains("rule34.paheal.net")){
      tagSearchEnabled = true;
      return "${booru.baseURL}/api/internal/autocomplete?s=$input"; // doesn't allow limit, but sorts by popularity
    } else {
      return "${booru.baseURL}/tags.json?search[name_matches]=$input*&limit=10";
    }
  }

  @override
  Future tagSearch(String input) async {
    List<String> searchTags = [];
    String url = makeTagURL(input);
    print("shimmie tag search $input $url");
    try {
      Uri uri = Uri.parse(url);
      final response = await http.get(uri,headers: {"Accept": "text/html,application/xml", "user-agent":"LoliSnatcher_Droid/$verStr"});
      // 200 is the success http response code
      print(response.body);
      if (response.statusCode == 200) {
        searchTags = response.body.substring(1,(response.body.length - 1)).replaceAll(new RegExp('(\:.([0-9])+)'), "").replaceAll("\"", "").split(",");
      }
    } catch(e) {
      print(e);
    }
    print(searchTags.length);
    return searchTags;
  }

  void searchCount(String input) async {
    int result = 0;
    if (booru.baseURL!.contains("rule34.paheal.net") && input != ''){ // paheal limits any search to 500 pages => empty input returns wrong count
      String url = makeURL(input);
      try {
        Uri uri = Uri.parse(url);
        final response = await http.get(uri, headers: {"Accept": "text/html,application/xml", "user-agent":"LoliSnatcher_Droid/$verStr"});
        // 200 is the success http response code
        if (response.statusCode == 200) {
          var parsedResponse = xml.parse(response.body);
          var root = parsedResponse.findAllElements('posts').toList();
          if(root.length == 1) {
            result = int.parse(root[0].getAttribute('count') ?? '0');
          }
        }
      } catch(e) {
        print(e);
      }
    }
    this.totalCount = result;
  }
}