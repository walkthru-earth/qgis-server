// QList<qint64> mapped type for SIP 6.8 on Ubuntu Noble (Qt 6.4)
// Ubuntu Noble's PyQt6 lacks this mapped type because it was built against Qt < 6.5.
// This will be unnecessary once the base image moves to Ubuntu 25.04+ with Qt 6.8+.

%MappedType QList<qint64>
{
%TypeHeaderCode
#include <QList>
%End

%ConvertFromTypeCode
  PyObject *l;

  if ((l = PyList_New(sipCpp->size())) == NULL)
    return NULL;

  QList<qint64>::iterator it = sipCpp->begin();
  for (int i = 0; it != sipCpp->end(); ++it, ++i)
  {
    PyObject *tobj;

    if ((tobj = PyLong_FromLongLong(*it)) == NULL)
    {
      Py_DECREF(l);
      return NULL;
    }
    PyList_SET_ITEM(l, i, tobj);
  }

  return l;
%End

%ConvertToTypeCode
  if (sipIsErr == NULL)
    return PyList_Check(sipPy);

  QList<qint64> *qlist = new QList<qint64>;

  for (int i = 0; i < PyList_GET_SIZE(sipPy); ++i)
  {
    *qlist << PyLong_AsLongLong(PyList_GET_ITEM(sipPy, i));
  }

  *sipCppPtr = qlist;
  return sipGetState(sipTransferObj);
%End
};
