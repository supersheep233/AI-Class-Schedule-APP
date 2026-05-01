package com.example.class_schedule

// 在文件头部补充导入：
import android.text.Html
import java.util.Calendar
import java.text.SimpleDateFormat
import java.util.Locale
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetLaunchIntent // 新增导入
import org.json.JSONArray

class CourseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_today_courses)

            // --- 新增：设置点击唤醒 App 的事件 ---
            // 创建一个能够唤醒 MainActivity 并携带自定义 URI 的 Intent
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("scheduleapp://main_schedule") // 自定义的 URI 标识
            )
            // 将点击事件绑定到我们刚才设定的 widget_root 上
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            // ------------------------------------

            // 读取由 Flutter 存入的 SharedPreference 数据
            val widgetData = HomeWidgetPlugin.getData(context)
            val coursesJsonStr = widgetData.getString("all_courses", "[]") // 读取全学期课表
            val startDateStr = widgetData.getString("semester_start_date", "")
            val totalWeeks = widgetData.getInt("semester_total_weeks", 20)

            val contentBuilder = java.lang.StringBuilder()

            try {
                val calendar = Calendar.getInstance()
                
                // 1. 计算星期几 (Flutter 中 1=周一, 7=周日)
                var todayDayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) - 1
                if (todayDayOfWeek == 0) todayDayOfWeek = 7

                // 1.5 格式化当前日期和星期以显示在标题上
                val dateFormat = SimpleDateFormat("MM月dd日", Locale.getDefault())
                val dateString = dateFormat.format(calendar.time)
                val weekDayString = when (todayDayOfWeek) {
                    1 -> "周一"
                    2 -> "周二"
                    3 -> "周三"
                    4 -> "周四"
                    5 -> "周五"
                    6 -> "周六"
                    7 -> "周日"
                    else -> ""
                }
                views.setTextViewText(R.id.tv_widget_title, "$dateString $weekDayString 课程")
                
                // 2. 计算当前是第几周
                var calculatedWeek = 1
                if (!startDateStr.isNullOrEmpty()) {
                    try {
                        val datePart = startDateStr.split("T")[0]
                        val dateParts = datePart.split("-")
                        val startCalendar = Calendar.getInstance()
                        startCalendar.set(dateParts[0].toInt(), dateParts[1].toInt() - 1, dateParts[2].toInt(), 0, 0, 0)
                        startCalendar.set(Calendar.MILLISECOND, 0)
                        
                        val todayCalendar = Calendar.getInstance()
                        todayCalendar.set(Calendar.HOUR_OF_DAY, 0)
                        todayCalendar.set(Calendar.MINUTE, 0)
                        todayCalendar.set(Calendar.SECOND, 0)
                        todayCalendar.set(Calendar.MILLISECOND, 0)

                        val diffMillis = todayCalendar.timeInMillis - startCalendar.timeInMillis
                        val daysDiff = (diffMillis / (1000 * 60 * 60 * 24)).toInt()
                        calculatedWeek = (daysDiff / 7) + 1
                        
                        if (calculatedWeek < 1) calculatedWeek = 1
                        if (calculatedWeek > totalWeeks) calculatedWeek = totalWeeks
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }

                // 3. 过滤并排序今日课程
                val allArray = JSONArray(coursesJsonStr)
                val rawJsonList = java.util.ArrayList<org.json.JSONObject>()
                
                for (i in 0 until allArray.length()) {
                    val obj = allArray.getJSONObject(i)
                    if (obj.getInt("dayOfWeek") == todayDayOfWeek) {
                        val weeksArray = obj.getJSONArray("weeks")
                        var inWeek = false
                        for (j in 0 until weeksArray.length()) {
                            if (weeksArray.getInt(j) == calculatedWeek) {
                                inWeek = true
                                break
                            }
                        }
                        if (inWeek) {
                            rawJsonList.add(obj)
                        }
                    }
                }
                rawJsonList.sortBy { it.getInt("startSlot") }

                // 4. 合并相邻且相同的课程
                val jsonList = java.util.ArrayList<org.json.JSONObject>()
                for (obj in rawJsonList) {
                    if (jsonList.isEmpty()) {
                        // 使用 toString() 重新构建 JSONObject，防止修改原数据
                        jsonList.add(org.json.JSONObject(obj.toString()))
                    } else {
                        val lastObj = jsonList[jsonList.size - 1]
                        val isAdjacent = lastObj.getInt("endSlot") + 1 == obj.getInt("startSlot")
                        val isSameName = lastObj.getString("name") == obj.getString("name")
                        val isSameRoom = lastObj.getString("room") == obj.getString("room")
                        val isSameTeacher = lastObj.optString("teacher", "") == obj.optString("teacher", "")

                        // 如果课程相邻且信息完全一致，则合并
                        if (isAdjacent && isSameName && isSameRoom && isSameTeacher) {
                            lastObj.put("endSlot", obj.getInt("endSlot"))
                            // 合并时间：将结束时间更新为最后一节课的结束时间
                            if (obj.has("endTime")) {
                                lastObj.put("endTime", obj.getString("endTime"))
                            }
                        } else {
                            jsonList.add(org.json.JSONObject(obj.toString()))
                        }
                    }
                }

                if (jsonList.isEmpty()) {
                    contentBuilder.append("今天没有课，好好休息！🎉")
                } else {
                    // 获取当前时间的总分钟数，方便做大小对比
                    val currentHour = calendar.get(Calendar.HOUR_OF_DAY)
                    val currentMinute = calendar.get(Calendar.MINUTE)
                    val currentTotalMinutes = currentHour * 60 + currentMinute

                    var isNextFound = false // 标记是否已经找到了“当前或下一节课”

                    for (i in 0 until jsonList.size) {
                        val obj = jsonList[i]
                        val name = obj.getString("name")
                        val room = obj.getString("room")
                        // 👈 新增：使用 optString 防止因为本地存有旧格式数据而引发崩溃
                        val teacher = obj.optString("teacher", "未知教师")
                        val startSlot = obj.getInt("startSlot")
                        val endSlot = obj.getInt("endSlot")
                        val startTimeStr = obj.optString("startTime", "00:00")
                        val endTimeStr = obj.optString("endTime", "23:59")

                        val startParts = startTimeStr.split(":")
                        var startTotalMinutes = 0
                        if (startParts.size == 2) {
                            startTotalMinutes = startParts[0].toInt() * 60 + startParts[1].toInt()
                        }

                        val endParts = endTimeStr.split(":")
                        var endTotalMinutes = 0
                        if (endParts.size == 2) {
                            endTotalMinutes = endParts[0].toInt() * 60 + endParts[1].toInt()
                        }

                        if (currentTotalMinutes > endTotalMinutes) {
                            // 已结束
                            contentBuilder.append("<font color='#999999'>✓ [已结束] $name | $startTimeStr-$endTimeStr (第${startSlot}-${endSlot}节)</font><br>")
                            contentBuilder.append("<font color='#999999'>📍 $room | 👨‍🏫 $teacher</font><br><br>")
                        } else if (currentTotalMinutes in startTotalMinutes..endTotalMinutes) {
                            // 正在上课
                            val remain = endTotalMinutes - currentTotalMinutes
                            contentBuilder.append("<b><font color='#E53935'>🔥 [正在上课] $name (距下课约 $remain 分钟)</font></b><br>")
                            contentBuilder.append("<b><font color='#E53935'>📍 $room | 👨‍🏫 $teacher | $startTimeStr-$endTimeStr (第${startSlot}-${endSlot}节)</font></b><br><br>")
                        } else {
                            // 即将开始
                            val wait = startTotalMinutes - currentTotalMinutes
                            val waitStr = if (wait >= 60) "${wait / 60}小时${wait % 60}分" else "${wait}分钟"
                            // 第一个即将开始的课高亮显示
                            if (!isNextFound) {
                                contentBuilder.append("<b><font color='#1E88E5'>⏳ [即将开始] $name ($waitStr 后)</font></b><br>")
                                contentBuilder.append("<b><font color='#1E88E5'>📍 $room | 👨‍🏫 $teacher | $startTimeStr-$endTimeStr (第${startSlot}-${endSlot}节)</font></b><br><br>")
                                isNextFound = true
                            } else {
                                contentBuilder.append("<font color='#333333'>📚 [未开始] $name ($waitStr 后)</font><br>")
                                contentBuilder.append("<font color='#555555'>📍 $room | 👨‍🏫 $teacher | $startTimeStr-$endTimeStr (第${startSlot}-${endSlot}节)</font><br><br>")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                contentBuilder.append("解析课程数据失败")
            }

            // 更新 UI：将 StringBuilder 的内容按 HTML 格式解析给 TextView
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                views.setTextViewText(R.id.tv_courses_content, Html.fromHtml(contentBuilder.toString().trim(), Html.FROM_HTML_MODE_COMPACT))
            } else {
                @Suppress("DEPRECATION")
                views.setTextViewText(R.id.tv_courses_content, Html.fromHtml(contentBuilder.toString().trim()))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
